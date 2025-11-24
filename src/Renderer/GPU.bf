namespace Treasure.Renderer;
using System;
using System.Collections;
using System.Diagnostics;
using SDL3;
using Treasure.Util;
using Treasure.UI;

struct GPUFrameReadback
{
    public SDL_GPUFence* fence;
    public SDL_GPUTransferBuffer* download_transfer_buffer;
    public int32[2] dim;
    public bool out_of_screen;
}

class GPU
{
    private bool GPU_USE_MSAA = true;
    private int GPU_SHADOW_MAP_DIM = 2048 * 2;
    private bool GPU_ENABLE_BACKFACE_CULL = false;
    private float GPU_CLEAR_DEPTH_FLOAT = 1.0f;
    private float GPU_CLEAR_COLOR_R = 0.78f;
    private float GPU_CLEAR_COLOR_G = 0.78f;
    private float GPU_CLEAR_COLOR_B = 0.96f;
    private float GPU_CLEAR_COLOR_A = 1.0f;

    public SDL_GPUDevice* device;
    public GPUBATCHState mem;

    public Queue<GPUFrameReadback> readback_queue;

    public SDL_GPUTexture* tex_msaa;
    public SDL_GPUTexture* tex_resolve;
    public SDL_GPUTexture* tex_world_depth;
    public SDL_GPUTexture* tex_mouse_picking_depth;
    public SDL_GPUTexture* tex_mouse_picking;

    public SDL_GPUTexture* shadow_tex;
    public SDL_GPUSampler* shadow_sampler;

    public SDL_GPUTexture* dummy_shadow_tex; // bound in shadowmap prepass; @todo delete?
    public SDL_GPUBuffer* dummy_instance_buffer;

    // pipeline, sample settings
    public SDL_GPUSampleCount sample_count;
    public SDL_GPUGraphicsPipeline*[2] world_pipelines; // 0: 4xMSAA; 1: no AA (for shadow mapping)
    public SDL_GPUGraphicsPipeline* ui_pipeline;

    public int bound_uniform_hash;
    public WorldUniform world_uniform;

    public SDL_GPUSampler* mesh_tex_sampler;

    public UIRenderer ui;
    // sdl properties
    public SDL_PropertiesID clear_depth_props;
    public SDL_PropertiesID clear_mouse_picking_props;
    public SDL_PropertiesID clear_color_props;

    public SDL_Window* window;

    public ASSETState assetState;
    public World world;
    public Application app;

    public void GPUInit()
    {
        // preapre props
        {
            this.clear_depth_props = SDL_CreateProperties();
            SDL_SetFloatProperty(
                this.clear_depth_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_DEPTH_FLOAT,
                this.GPU_CLEAR_DEPTH_FLOAT);

            this.clear_mouse_picking_props = SDL_CreateProperties();
            SDL_SetFloatProperty(
                this.clear_mouse_picking_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_R_FLOAT, 0.0f);
            SDL_SetFloatProperty(this.clear_mouse_picking_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_G_FLOAT, 0.0f);
            SDL_SetFloatProperty(this.clear_mouse_picking_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_B_FLOAT, 0.0f);
            SDL_SetFloatProperty(this.clear_mouse_picking_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_A_FLOAT, 0.0f);

            this.clear_color_props = SDL_CreateProperties();
            SDL_SetFloatProperty(this.clear_color_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_R_FLOAT, this.GPU_CLEAR_COLOR_R);
            SDL_SetFloatProperty(this.clear_color_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_G_FLOAT, this.GPU_CLEAR_COLOR_G);
            SDL_SetFloatProperty(this.clear_color_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_B_FLOAT, this.GPU_CLEAR_COLOR_B);
            SDL_SetFloatProperty(this.clear_color_props,
                SDL_PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_A_FLOAT, this.GPU_CLEAR_COLOR_A);
        }

        // check for msaa 4 support
        this.sample_count = .SDL_GPU_SAMPLECOUNT_1;
        if (this.GPU_USE_MSAA)
        {
            SDL_GPUTextureFormat tex_format =
                SDL_GetGPUSwapchainTextureFormat(this.device, this.window);
            bool supports_msaa =
                SDL_GPUTextureSupportsSampleCount(this.device, tex_format, .SDL_GPU_SAMPLECOUNT_4);
            if (supports_msaa)
            {
                this.sample_count = .SDL_GPU_SAMPLECOUNT_4;
            }
        }

        // Texture sampler
        {
            SDL_GPUSamplerCreateInfo sampler_info = SDL_GPUSamplerCreateInfo()
            {
                min_filter = .SDL_GPU_FILTER_LINEAR,
                mag_filter = .SDL_GPU_FILTER_LINEAR,
                mipmap_mode = .SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
                address_mode_u = .SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
                address_mode_v = .SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
                address_mode_w = .SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
                min_lod = 0,
                max_lod = 100
            };
            this.mesh_tex_sampler = SDL_CreateGPUSampler(this.device, &sampler_info);
        }

        this.CreateBuffer(
            SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            1024 * 1024, "Dummy instance storage buffer",
            out this.dummy_instance_buffer);

        // Shadow map
        {
            this.CreateDepthTexture((uint32)GPU_SHADOW_MAP_DIM, (uint32)GPU_SHADOW_MAP_DIM,
                true, true,
                out this.shadow_tex);
            this.CreateDepthTexture(16, 16, true, true, out this.dummy_shadow_tex);

            SDL_GPUSamplerCreateInfo sampler_info = SDL_GPUSamplerCreateInfo()
            {
                min_filter = .SDL_GPU_FILTER_LINEAR,
                mag_filter = .SDL_GPU_FILTER_LINEAR,
                mipmap_mode = .SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
                address_mode_u = .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                address_mode_v = .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                address_mode_w = .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                min_lod = 0,
                max_lod = 100
            };
            this.shadow_sampler = SDL_CreateGPUSampler(this.device, &sampler_info);
        }

        // UI sampler
        {
            SDL_GPUSamplerCreateInfo sampler_info = SDL_GPUSamplerCreateInfo()
            {
                min_filter = .SDL_GPU_FILTER_LINEAR,
                mag_filter = .SDL_GPU_FILTER_LINEAR
            };
            this.ui.gpu_atlas_sampler = SDL_CreateGPUSampler(this.device, &sampler_info);
        }

        // UI buffers
        this.CreateBuffer(
            SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_INDEX,
            sizeof(uint32), "UI Index Buffer", out this.ui.gpu_indices);
        this.CreateBuffer(
            SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            sizeof(UIShape), "UI Shapes Storage Buffer", out this.ui.gpu_shape_buffer);
        this.CreateBuffer(
            SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            sizeof(Rect), "UI Clips Storage Buffer", out this.ui.gpu_clip_buffer);

        this.InitPipelines();
        this.ResizeFramebuffer();
    }

    public void InitPipelines()
    {
        // Release pipelines if they exist
        {
            for (let it in this.world_pipelines)
            {
                SDL_ReleaseGPUGraphicsPipeline(this.device, it);
                SDL_ReleaseGPUGraphicsPipeline(this.device, this.ui_pipeline);
            }
        }

        SDL_GPUColorTargetDescription color_desc = SDL_GPUColorTargetDescription()
        {
            format = SDL_GetGPUSwapchainTextureFormat(this.device, this.window),
        };

        // WORLD pipeline
        {
            String binary_vs;
            String binary_ps;
            this.assetState.GetShader(.WORLD_VS, out binary_vs);
            this.assetState.GetShader(.WORLD_PS, out binary_ps);

            SDL_GPUShaderCreateInfo create_info = SDL_GPUShaderCreateInfo()
            {
                stage = .SDL_GPU_SHADERSTAGE_VERTEX,
                num_samplers = 0,
                num_storage_buffers = 2,
                num_storage_textures = 0,
                num_uniform_buffers = 1,

                format = SDL_GPUShaderFormat.SDL_GPU_SHADERFORMAT_DXIL,
                code = (uint8*)binary_vs.CStr(),
                code_size = (uint)binary_vs.Length,
                entrypoint = "World_DxShaderSkinnedVS"
            };
            SDL_GPUShader* vertex_shader = SDL_CreateGPUShader(this.device, &create_info);

            create_info = SDL_GPUShaderCreateInfo()
            {
                stage = .SDL_GPU_SHADERSTAGE_FRAGMENT,
                num_samplers = 2,
                num_storage_buffers = 0,
                num_storage_textures = 0,
                num_uniform_buffers = 1,

                format = SDL_GPUShaderFormat.SDL_GPU_SHADERFORMAT_DXIL,
                code = (uint8*)binary_ps.CStr(),
                code_size = (uint)binary_ps.Length,
                entrypoint = "World_DxShaderSkinnedPS"
            };
            SDL_GPUShader* fragment_shader = SDL_CreateGPUShader(this.device, &create_info);

            SDL_GPUGraphicsPipelineCreateInfo pipeline = SDL_GPUGraphicsPipelineCreateInfo()
            {
                vertex_shader = vertex_shader,
                fragment_shader = fragment_shader,
                multisample_state = SDL_GPUMultisampleState()
                {
                    sample_count = this.sample_count
                },
                depth_stencil_state = .()
                {
                    enable_depth_test = true,
                    enable_depth_write = true,
                    compare_op = .SDL_GPU_COMPAREOP_LESS
                },
                primitive_type = .SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
                rasterizer_state = .()
                {
                    front_face = .SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
                    cull_mode =
                        this.GPU_ENABLE_BACKFACE_CULL ? .SDL_GPU_CULLMODE_BACK : .SDL_GPU_CULLMODE_NONE,
                    enable_depth_clip = true
                },
                target_info = .()
                {
                    num_color_targets = 1,
                    color_target_descriptions = &color_desc,
                    depth_stencil_format = .SDL_GPU_TEXTUREFORMAT_D16_UNORM,
                    has_depth_stencil_target = true,
                },
                props = 0
            };

            SDL_GPUVertexBufferDescription[1] VERTEX_BUFFERS;
            VERTEX_BUFFERS[0] = .()
            {
                slot = 0,
                pitch = sizeof(WorldVertex),
                input_rate = .SDL_GPU_VERTEXINPUTRATE_VERTEX,
                instance_step_rate = 0
            };
            pipeline.vertex_input_state.num_vertex_buffers = VERTEX_BUFFERS.Count;
            pipeline.vertex_input_state.vertex_buffer_descriptions = &VERTEX_BUFFERS;

            SDL_GPUVertexAttribute[?] VERTEX_ATTRIBS = .(
                .()
                {
                    format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    location = 0,
                    offset = 0
                },
                .()
                {
                    format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    location = 1,
                    offset = sizeof(Vector3f)
                },
                .()
                {
                    format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    location = 2,
                    offset = 2 * sizeof(Vector3f)
                },
                .()
                {
                    format = .SDL_GPU_VERTEXELEMENTFORMAT_UINT,
                    location = 3,
                    offset = 2 * sizeof(Vector3f) + sizeof(Vector2f)
                },
                .()
                {
                    format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                    location = 4,
                    offset = 8 * sizeof(float) + sizeof(uint32)
                },
            );
            pipeline.vertex_input_state.num_vertex_attributes = VERTEX_ATTRIBS.Count;
            pipeline.vertex_input_state.vertex_attributes = &VERTEX_ATTRIBS;

            // Create main pipeline
            this.world_pipelines[0] = SDL_CreateGPUGraphicsPipeline(this.device, &pipeline);
            Debug.Assert(this.world_pipelines[0] != null);

            // Modify pipeline settings for shadow mapping depth pass
            pipeline.multisample_state.sample_count = .SDL_GPU_SAMPLECOUNT_1;
            pipeline.rasterizer_state.cull_mode = .SDL_GPU_CULLMODE_NONE;

            // Create shadow pass pipeline
            this.world_pipelines[1] = SDL_CreateGPUGraphicsPipeline(this.device, &pipeline);
            Debug.Assert(this.world_pipelines[1] != null);

            SDL_ReleaseGPUShader(this.device, vertex_shader);
            SDL_ReleaseGPUShader(this.device, fragment_shader);
        }

        // UI pipeline
        {
            String binary_vs;
            String binary_ps;
            this.assetState.GetShader(.UI_VS, out binary_vs);
            this.assetState.GetShader(.UI_PS, out binary_ps);

            SDL_GPUShaderCreateInfo create_info = SDL_GPUShaderCreateInfo()
            {
                stage = .SDL_GPU_SHADERSTAGE_VERTEX,
                num_samplers = 0,
                num_storage_buffers = 2,
                num_storage_textures = 0,
                num_uniform_buffers = 1,

                format = SDL_GPUShaderFormat.SDL_GPU_SHADERFORMAT_DXIL,
                code = (uint8*)binary_vs.CStr(),
                code_size = (uint)binary_vs.Length,
                entrypoint = "UI_DxShaderVS"
            };
            SDL_GPUShader* vertex_shader = SDL_CreateGPUShader(this.device, &create_info);

            create_info = SDL_GPUShaderCreateInfo()
            {
                stage = .SDL_GPU_SHADERSTAGE_FRAGMENT,
                num_samplers = 1,
                num_storage_buffers = 0,
                num_storage_textures = 0,
                num_uniform_buffers = 0,

                format = .SDL_GPU_SHADERFORMAT_DXIL,
                code = (uint8*)binary_ps.CStr(),
                code_size = (uint8)binary_ps.Length,
                entrypoint = "UI_DxShaderPS"
            };
            SDL_GPUShader* fragment_shader = SDL_CreateGPUShader(this.device, &create_info);

            SDL_GPUColorTargetDescription ui_color_desc = SDL_GPUColorTargetDescription()
            {
                format = color_desc.format,
                blend_state = .()
                {
                    src_color_blendfactor = .SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    dst_color_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    color_blend_op = .SDL_GPU_BLENDOP_ADD,
                    // use ONE, ONE instead?
                    src_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    dst_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    alpha_blend_op = .SDL_GPU_BLENDOP_ADD,
                    enable_blend = true
                }
            };

            SDL_GPUGraphicsPipelineCreateInfo pipeline = SDL_GPUGraphicsPipelineCreateInfo()
            {
                vertex_shader = vertex_shader,
                fragment_shader = fragment_shader,
                primitive_type = .SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
                target_info = .()
                {
                    num_color_targets = 1,
                    color_target_descriptions = &ui_color_desc
                }
            };
            this.ui_pipeline = SDL_CreateGPUGraphicsPipeline(this.device, &pipeline);

            SDL_ReleaseGPUShader(this.device, vertex_shader);
            SDL_ReleaseGPUShader(this.device, fragment_shader);
        }
    }

    public enum RenderMode
    {
        RENDER,
        DEPTH
    }

    public void RenderWorld(SDL_GPUCommandBuffer* cmd, SDL_GPURenderPass* pass,
        RenderMode mode)
    {
        bool simplified_pipeline = mode != .RENDER;
        int pipeline_index = simplified_pipeline ? 1 : 0;
        SDL_BindGPUGraphicsPipeline(pass, this.world_pipelines[pipeline_index]);

        // Bind shadow texture sampler to fragment shader
        {
            SDL_GPUTextureSamplerBinding binding_sampl = SDL_GPUTextureSamplerBinding()
            {
                texture = simplified_pipeline ? this.dummy_shadow_tex : this.shadow_tex,
                sampler = this.shadow_sampler,
            };
            SDL_BindGPUFragmentSamplers(pass, 0, &binding_sampl, 1);
        }

        // Bind dummy buffers
        {
            Span<GPUBatch> poses;
            this.mem.GetPosesBatch(out poses);
            SDL_GPUBuffer*[2] storage_bufs = .(
                this.dummy_instance_buffer,
                poses[0].buffer.handle
            );
            SDL_BindGPUVertexStorageBuffers(pass, 0, &storage_bufs, storage_bufs.Count);
        }
        //
        // Dynamic meshes
        //
        for (int batch_index = 0; batch_index < this.mem.batches_count; batch_index++)
        {
            GPUBatch gpu_verts = this.mem.batches[batch_index];
            if (gpu_verts.target.type != .MeshVertices)
            {
                continue;
            }
            if (gpu_verts.element_count == 0)
            {
                continue;
            }

            // Bind vertex buffer
            SDL_BindGPUVertexBuffers(pass, 0, 
                &(SDL_GPUBufferBinding(){ buffer = gpu_verts.buffer.handle }), 1);

            Material material;
            assetState.GetMaterial(gpu_verts.target.material_key, 0, out material);

            // Uniforms
            world.ApplyMaterialToUniform(ref this.world_uniform, material, simplified_pipeline);
            this.world_uniform.flags |= material.shaderFlags;
            this.UpdateWorldUniform(cmd, ref this.world_uniform);

            // Bind texture
            SDL_GPUTextureSamplerBinding binding_sampl = SDL_GPUTextureSamplerBinding()
            {
                texture = material.stex,
                sampler = this.mesh_tex_sampler,
            };
            SDL_BindGPUFragmentSamplers(pass, 1, &binding_sampl, 1);

            SDL_DrawGPUPrimitives(pass, gpu_verts.element_count, 1, 0, 0);
        }

        //
        // Prepare GPU state to render models
        //
        // Bind model vertices & indices
        SDL_BindGPUVertexBuffers(pass, 0,
            &(SDL_GPUBufferBinding(){ buffer = assetState.model_vertices }), 1);
        SDL_BindGPUIndexBuffer(pass,
            &(SDL_GPUBufferBinding(){ buffer = assetState.model_indices }),
            .SDL_GPU_INDEXELEMENTSIZE_16BIT);

        //
        // Models
        //
        for (int batch_index = 0; batch_index < this.mem.batches_count; batch_index++)
        {
            if (this.mem.batches[batch_index].target.type != .ModelInstances)
            {
                continue;
            }
            if (this.mem.batches[batch_index].element_count == 0)
            {
                continue;
            }

            Model model;
            assetState.GetModel(this.mem.batches[batch_index].target.model_key, out model);

            // bind instance storage buffer
            Span<GPUBatch> poses;
            this.mem.GetPosesBatch(out poses);
            SDL_GPUBuffer*[2] storage_bufs = .(
                this.mem.batches[batch_index].buffer.handle,
                poses[0].buffer.handle,
            );
            SDL_BindGPUVertexStorageBuffers(pass, 0, &storage_bufs, storage_bufs.Count);

            for (let mesh in model.meshes)
            {
                Material material;
                assetState.GetMaterial(mesh.material, 0, out material);

                // Uniforms
                world.ApplyMaterialToUniform(ref this.world_uniform, material, simplified_pipeline);
                this.world_uniform.flags |= .UseInstanceBuffer;
                if (model.is_skinned)
                {
                    this.world_uniform.flags |= .DoMeshSkinning;
                }
                this.UpdateWorldUniform(cmd, ref this.world_uniform);

                // Bind texture
                if (material.has_texture)
                {
                    SDL_GPUTextureSamplerBinding binding_sampl =
                        SDL_GPUTextureSamplerBinding()
                        {
                        texture = material.stex,
                        sampler = this.mesh_tex_sampler,
                    };
                    SDL_BindGPUFragmentSamplers(pass, 1, &binding_sampl, 1);
                }

                SDL_DrawGPUIndexedPrimitives(
                    pass, (uint32)mesh.indices_count,
                    this.mem.batches[batch_index].element_count,
                    (uint32)mesh.indices_start_index,
                    (int32)mesh.vertices_start_index, 0);
            }
        }
    }

    public void Iterate()
    {
        SDL_GPUCommandBuffer* cmd = SDL_AcquireGPUCommandBuffer(this.device);
        SDL_GPUTexture* swapchain_tex = null;
        uint32 draw_width = 0;
        uint32 draw_height = 0;
        SDL_WaitAndAcquireGPUSwapchainTexture(
            cmd, this.window, &swapchain_tex, &draw_width, &draw_height);

        if (swapchain_tex == null)
        {
            SDL_CancelGPUCommandBuffer(cmd);
            return;
        }

        mem.UploadAllBatches(this.device, cmd);

        SDL_GPUDepthStencilTargetInfo depth_target = SDL_GPUDepthStencilTargetInfo()
        {
            clear_depth = GPU_CLEAR_DEPTH_FLOAT,
            load_op = .SDL_GPU_LOADOP_CLEAR,
            store_op = .SDL_GPU_STOREOP_DONT_CARE,
            stencil_load_op = .SDL_GPU_LOADOP_DONT_CARE,
            stencil_store_op = .SDL_GPU_STOREOP_DONT_CARE,
            cycle = true
        };

        // Sun shadow map render pass
        {
            depth_target.texture = this.shadow_tex;
            SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(cmd, null, 0, &depth_target);
            this.RenderWorld(cmd, pass, .DEPTH);
            SDL_EndGPURenderPass(pass);
        }

        // World render pass
        {
            depth_target.texture = this.tex_world_depth;

            SDL_GPUColorTargetInfo color_target = SDL_GPUColorTargetInfo()
            {
                clear_color = .(){
                    r = GPU_CLEAR_COLOR_R,
                    g = GPU_CLEAR_COLOR_G,
                    b = GPU_CLEAR_COLOR_B,
                    a = GPU_CLEAR_COLOR_A,
                },
                load_op = .SDL_GPU_LOADOP_CLEAR,
                store_op = .SDL_GPU_STOREOP_STORE
            };

            if (this.tex_msaa != null)
            {
                color_target.store_op = .SDL_GPU_STOREOP_RESOLVE;
                color_target.texture = this.tex_msaa;
                color_target.resolve_texture = this.tex_resolve;
                color_target.cycle = true;
                color_target.cycle_resolve_texture = true;
            }
            else
            {
                color_target.texture = swapchain_tex;
            }

            SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(cmd, &color_target, 1, &depth_target);
            this.RenderWorld(cmd, pass, .RENDER);
            SDL_EndGPURenderPass(pass);
        }

        if (this.sample_count > .SDL_GPU_SAMPLECOUNT_1)
        {
            SDL_GPUBlitInfo blit = SDL_GPUBlitInfo()
            {
                source = .{
                    texture = this.tex_resolve,
                    w = app.window_dim[0],
                    h = app.window_dim[1],
                },
                destination = .{
                    texture = swapchain_tex,
                    w = draw_width,
                    h = draw_height,
                },
                load_op = .SDL_GPU_LOADOP_DONT_CARE,
                filter = .SDL_GPU_FILTER_LINEAR
            };
            SDL_BlitGPUTexture(cmd, &blit);
        }

        // UI render pass
        if (this.ui.indices_count > 0)
        {
            // Upload uniform
            UIUniform uniform = UIUniform()
            {
                window_dim = Vector2f(app.window_dim[0], app.window_dim[1]),
                texture_dim = Vector2f(this.ui.font.texture_dim, this.ui.font.texture_dim)
            };
            this.UpdateUIUniform(cmd, ref uniform);

            // Upload buffers to GPU
            {
                uint32 transfer_size = sizeof(uint32) * this.ui.indices_count;
                this.TransferBuffer(cmd, this.ui.gpu_indices,
                    &this.ui.indices, transfer_size);
            }
            if (this.ui.shapes_count > 0)
            {
                uint32 transfer_size = sizeof(UIShape) * this.ui.shapes_count;
                this.TransferBuffer(cmd, this.ui.gpu_shape_buffer,
                    &this.ui.shapes, transfer_size);
            }
            if (this.ui.clips_count > 0)
            {
                uint32 transfer_size = sizeof(UIClip) * this.ui.clips_count;
                this.TransferBuffer(cmd, this.ui.gpu_clip_buffer,
                    &this.ui.clips, transfer_size);
            }

            // Start pass
            SDL_GPUColorTargetInfo color_target = SDL_GPUColorTargetInfo()
            {
                load_op = .SDL_GPU_LOADOP_LOAD,
                store_op = .SDL_GPU_STOREOP_STORE,
                texture = swapchain_tex
            };
            SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(cmd, &color_target, 1, null);

            // Bind pipeline
            SDL_BindGPUGraphicsPipeline(pass, this.ui_pipeline);

            // Bind texture & sampler
            SDL_GPUTextureSamplerBinding sampler_binding = SDL_GPUTextureSamplerBinding()
            {
                texture = this.ui.gpu_atlas_texture,
                sampler = this.ui.gpu_atlas_sampler
            };
            SDL_BindGPUFragmentSamplers(pass, 0, &sampler_binding, 1);

            // Bind storage buffers
            SDL_GPUBuffer*[2] storage_bufs = .(
                this.ui.gpu_shape_buffer,
                this.ui.gpu_clip_buffer
            );
            SDL_BindGPUVertexStorageBuffers(pass, 0, &storage_bufs, storage_bufs.Count);

            // Bind index buffer
            SDL_GPUBufferBinding binding_ind = SDL_GPUBufferBinding()
            {
                buffer = this.ui.gpu_indices
            };
            SDL_BindGPUIndexBuffer(pass, &binding_ind, .SDL_GPU_INDEXELEMENTSIZE_32BIT);

            // Draw
            SDL_DrawGPUIndexedPrimitives(pass, this.ui.indices_count, 1, 0, 0, 0);

            // End pass
            SDL_EndGPURenderPass(pass);
        }

        SDL_SubmitGPUCommandBuffer(cmd);
    }

    public void ResizeFramebuffer()
    {
        SDL_ReleaseGPUTexture(this.device, this.tex_world_depth);
        SDL_ReleaseGPUTexture(this.device, this.tex_mouse_picking_depth);
        SDL_ReleaseGPUTexture(this.device, this.tex_msaa);
        SDL_ReleaseGPUTexture(this.device, this.tex_resolve);
        SDL_ReleaseGPUTexture(this.device, this.tex_mouse_picking);

        uint32 window_width = app.window_dim[0];
        uint32 window_height = app.window_dim[1];
        this.CreateMSAATexture(window_width, window_height, out this.tex_msaa);
        this.CreateResolveTexture(window_width, window_height, out this.tex_resolve);
        this.CreateDepthTexture(window_width, window_height,
            false, false, out this.tex_world_depth);
    }

    public void CreateBuffer(SDL_GPUBufferUsageFlags usage,
        uint32 size, String name, out SDL_GPUBuffer* result)
    {
        SDL_GPUBufferCreateInfo desc = SDL_GPUBufferCreateInfo()
        {
            usage = usage, size = size
        };
        result = SDL_CreateGPUBuffer(this.device, &desc);
        Debug.Assert(result != null);
        if (name.IsEmpty == false)
        {
            SDL_SetGPUBufferName(this.device, result, name.CStr());
        }
    }

    public void CreateDepthTexture(uint32 width, uint32 height,
        bool used_in_sampler, bool sample_count_1, out SDL_GPUTexture* result)
    {
        SDL_GPUTextureCreateInfo info = SDL_GPUTextureCreateInfo()
        {
            type = .SDL_GPU_TEXTURETYPE_2D,
            format = .SDL_GPU_TEXTUREFORMAT_D16_UNORM,
            width = width,
            height = height,
            layer_count_or_depth = 1,
            num_levels = 1,
            sample_count = this.sample_count,
            usage = .SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
            props = this.clear_depth_props,
        };

        if (used_in_sampler)
        {
            info.usage |= .SDL_GPU_TEXTUREUSAGE_SAMPLER;
        }
        if (sample_count_1)
        {
            info.sample_count = .SDL_GPU_SAMPLECOUNT_1;
        }

        result = SDL_CreateGPUTexture(this.device, &info);
        Debug.Assert(result != null); // @todo report err
    }

    public void CreateMSAATexture(uint32 width, uint32 height, out SDL_GPUTexture* result)
    {
        if (this.sample_count == .SDL_GPU_SAMPLECOUNT_1)
        {
            result = null;
            return;
        }

        SDL_GPUTextureCreateInfo info = SDL_GPUTextureCreateInfo()
        {
            type = .SDL_GPU_TEXTURETYPE_2D,
            format = SDL_GetGPUSwapchainTextureFormat(this.device, this.window),
            width = width,
            height = height,
            layer_count_or_depth = 1,
            num_levels = 1,
            sample_count = this.sample_count,
            usage = .SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
            props = this.clear_color_props
        };

        result = SDL_CreateGPUTexture(this.device, &info);
        Debug.Assert(result != null); // @todo report err
    }

    public void CreateResolveTexture(uint32 width, uint32 height, out SDL_GPUTexture* result)
    {
        if (this.sample_count == .SDL_GPU_SAMPLECOUNT_1)
        {
            result = null;
            return;
        }

        SDL_GPUTextureCreateInfo info = SDL_GPUTextureCreateInfo()
        {
            type = .SDL_GPU_TEXTURETYPE_2D,
            format = SDL_GetGPUSwapchainTextureFormat(this.device, this.window),
            width = width,
            height = height,
            layer_count_or_depth = 1,
            num_levels = 1,
            sample_count = .SDL_GPU_SAMPLECOUNT_1,
            usage = .SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | .SDL_GPU_TEXTUREUSAGE_SAMPLER, // @todo remove SAMPLER?
            props = this.clear_color_props,
        };

        result = SDL_CreateGPUTexture(this.device, &info);
        Debug.Assert(result != null); // @todo report err
    }

    public void TransferBuffer(SDL_GPUCommandBuffer* cmd,
        SDL_GPUBuffer* gpu_buffer, void* data, uint32 data_size)
    {
        // create transfer buffer
        SDL_GPUTransferBufferCreateInfo trans_desc = SDL_GPUTransferBufferCreateInfo()
        {
            usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            size = data_size
        };
        SDL_GPUTransferBuffer* buf_transfer =
            SDL_CreateGPUTransferBuffer(this.device, &trans_desc);
        Debug.Assert(buf_transfer != null); // @todo report err

        // CPU memory -> GPU memory
        {
            void* map = SDL_MapGPUTransferBuffer(this.device, buf_transfer, false);
            Internal.MemCpy(map, data, data_size);
            SDL_UnmapGPUTransferBuffer(this.device, buf_transfer);
        }

        // GPU memory -> GPU buffers
        {
            SDL_GPUCopyPass* copy_pass = SDL_BeginGPUCopyPass(cmd);

            SDL_GPUTransferBufferLocation buf_location =
                SDL_GPUTransferBufferLocation()
            {
                transfer_buffer = buf_transfer,
                offset = 0
            };
            SDL_GPUBufferRegion dst_region = SDL_GPUBufferRegion()
            {
                buffer = gpu_buffer,
                offset = 0,
                size = data_size
            };
            SDL_UploadToGPUBuffer(copy_pass, &buf_location, &dst_region, false);

            SDL_EndGPUCopyPass(copy_pass);
        }

        SDL_ReleaseGPUTransferBuffer(this.device, buf_transfer);
    }

    public void UpdateWorldUniform(SDL_GPUCommandBuffer* cmd, ref WorldUniform uniform)
    {
        int uniform_hash = uniform.GetHashCode();
        if (this.bound_uniform_hash != uniform_hash)
        {
            SDL_PushGPUVertexUniformData(cmd, 0, &uniform, sizeof(WorldUniform));
            SDL_PushGPUFragmentUniformData(cmd, 0, &uniform, sizeof(WorldUniform));
        }
    }

    public void UpdateUIUniform(SDL_GPUCommandBuffer* cmd, ref UIUniform uniform)
    {
        int uniform_hash = uniform.GetHashCode();
        if (this.bound_uniform_hash != uniform_hash)
        {
            this.bound_uniform_hash = uniform_hash;
            SDL_PushGPUVertexUniformData(cmd, 0, &uniform, sizeof(UIUniform));
        }
    }

    public void Deinit()
    {
        for (let it in this.world_pipelines)
        {
            SDL_ReleaseGPUGraphicsPipeline(this.device, it);
        }
        SDL_ReleaseGPUGraphicsPipeline(this.device, this.ui_pipeline);

        SDL_ReleaseGPUTexture(this.device, this.tex_msaa);
        SDL_ReleaseGPUTexture(this.device, this.tex_resolve);

        SDL_ReleaseGPUTexture(this.device, this.shadow_tex);
        SDL_ReleaseGPUSampler(this.device, this.shadow_sampler);

        SDL_ReleaseGPUTexture(this.device, this.dummy_shadow_tex);
        SDL_ReleaseGPUBuffer(this.device, this.dummy_instance_buffer);

        // Mesh
        SDL_ReleaseGPUSampler(this.device, this.mesh_tex_sampler);

        // UI
        SDL_ReleaseGPUTexture(this.device, this.ui.gpu_atlas_texture);
        SDL_ReleaseGPUSampler(this.device, this.ui.gpu_atlas_sampler);
        SDL_ReleaseGPUBuffer(this.device, this.ui.gpu_indices);
        SDL_ReleaseGPUBuffer(this.device, this.ui.gpu_shape_buffer);
        SDL_ReleaseGPUBuffer(this.device, this.ui.gpu_clip_buffer);
    }
}
