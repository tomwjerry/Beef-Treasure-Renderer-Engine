namespace Treasure.UI;
using System;
using System.Collections;
using System.Diagnostics;
using SDL3;
using Treasure.Renderer;
using Treasure.Util;

struct FontGlyph
{
    public int hash;
    public uint16[2] p;
    public uint16[2] dim;
    public uint8 layer;
    public uint16 next;
    // metrics
    public Vector2f bearing;
    public float advance;
    public Span<uint32> pixels;
}

struct FontLayer
{
    public uint16[Font.FONT_ATLAS_LAYER_MAX_LINES] line_heights;
    public uint16[Font.FONT_ATLAS_LAYER_MAX_LINES] line_advances;
    public uint16 line_count;

    public FontGlyph[Font.FONT_ATLAS_LAYER_MAX_GLYPHS] hash_table;
    public FontGlyph[Font.FONT_ATLAS_LAYER_MAX_GLYPHS] collision_array;
    public uint16 collision_count;
}

struct FaceMetrics
{
    public float ascent;
    public float descent;
    public float linespace;
}

struct FontFace
{
    public uint64 num_faces;
    public uint64 face_index;

    public uint32 face_flags;
    public uint32 style_flags;

    public uint64 num_glyphs;

    public StringView family_name;
    public StringView style_name;

    public uint32 num_fixed_sizes;

    public uint16 units_per_EM;
    public int16 ascender;
    public int16 descender;
    public int16 height;

    public int16 max_advance_width;
    public int16 max_advance_height;

    public int16 underline_position;
    public int16 underline_thickness;
}

class Font
{
    public const int FONT_ATLAS_LAYERS = 4;
    public const int FONT_ATLAS_LAYER_MAX_LINES = 64;
    public const int FONT_ATLAS_LAYER_MAX_GLYPHS = 4096;
    public const int FONT_ATLAS_MARGIN = 1;

    public int32 err;

    public uint16 texture_dim;

    public FontLayer[FONT_ATLAS_LAYERS] layers;
    public uint8 active_layer_index;

    public List<FontFace> fontFaces;

    public void MaybeResizeAtlasTexture(GPU gpu)
    {
        float window_area = Math.Sqrt(gpu.app.window_dim[0] * gpu.app.window_dim[1]);
        uint32 new_texture_dim = Math.Max(CeilPow2((uint32)window_area), 512);

        // Do the atlas texture resize if new_texture_dim is 2x
        // too small or more than 2x too big compared to previous texture_dim.
        if (new_texture_dim >= texture_dim * 2 || new_texture_dim * 2 < texture_dim)
        {
            Logger.Log(
                "UI texture atlas resizing from {} to {}",
                ToString(.. scope .(texture_dim)),
                ToString(.. scope .(new_texture_dim)),
                .INFO);
            texture_dim = (uint16)new_texture_dim;

            SDL_ReleaseGPUTexture(gpu.device, gpu.ui.gpu_atlas_texture);
            SDL_GPUTextureCreateInfo tex_info = SDL_GPUTextureCreateInfo()
            {
                type = .SDL_GPU_TEXTURETYPE_2D_ARRAY,
                format = .SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
                width = texture_dim,
                height = texture_dim,
                layer_count_or_depth = FONT_ATLAS_LAYERS,
                num_levels = 1,
                usage = .SDL_GPU_TEXTUREUSAGE_SAMPLER
            };
            gpu.ui.gpu_atlas_texture = SDL_CreateGPUTexture(gpu.device, &tex_info);
            SDL_SetGPUTextureName(gpu.device, gpu.ui.gpu_atlas_texture, "UI Atlas Texture");

            // Pre-seed layers to be full.
            // This isn't necessary but will result in more optimal fill order.
            for (var it in layers)
            {
                it.line_count = 1;
                it.line_heights[0] = texture_dim;
                it.line_advances[0] = texture_dim;
            }
        }
    }

    public FaceMetrics GetFaceMetrics(uint8 fontFam, uint16 pixel_height)
    {
        FontFace ft_face = this.fontFaces[fontFam];
        //FT_Set_Pixel_Sizes(ft_face, 0, pixel_height);

        FaceMetrics result = FaceMetrics()
        {
            ascent = ft_face.ascender / 64.0f,
            descent = ft_face.descender / 64.0f,
            linespace = ft_face.height / 64.0f,
        };
        return result;
    }

    //
    // Glyphs in atlas
    //
    public int CodepointHash(uint32 codepoint, uint8 fontFam, uint16 pixel_height)
    {
        int hash = fontFam.GetHashCode() +
            pixel_height.GetHashCode() + codepoint.GetHashCode();
        return hash;
    }

    public FontGlyph FindGlyphInLayer(ref FontLayer layer, int hash, bool create_mode)
    {
        int key = hash % layer.hash_table.Count;
        FontGlyph slot = layer.hash_table[key];

        while (slot.hash != 0 && slot.hash != hash) // collision
        {
            if (slot.next != 0)// follow next index
            {
                slot = layer.collision_array[slot.next];
                continue;
            }

            // hash isn't matching, no next slot in chain
            if (!create_mode) // exit if not in create mode
            {
                break;
            }

            // chain new element from collision table
            if (layer.collision_count < layer.collision_array.Count)
            {
                slot.next = layer.collision_count;
                layer.collision_count += 1;
                slot = layer.collision_array[slot.next];
                break;
            }

            // all hope is lost, collision table is full
            break;
        }

        return slot;
    }

    public Result<FontGlyph> CreateGlyphInLayer(ref FontLayer layer, int hash,
        uint16 orig_width, uint16 orig_height)
    {
        if (orig_width <= 0 || orig_height <= 0)
        {
            FontGlyph slot = this.FindGlyphInLayer(ref layer, hash, true);
            if (slot.hash == 0)
            {
                slot.hash = hash;
                slot.layer = this.LayerIndexFromPointer(layer);
                return slot;
            }
            else
            {
                return .Err;
            }
        }

        uint16 margin = FONT_ATLAS_MARGIN;
        uint16 margin2 = margin * 2;

        uint16 width = orig_width + margin2;
        uint16 height = orig_height + margin2;
        uint16 max_dim = this.texture_dim;
        uint16 all_lines_height = 0;

        // find best line
        uint32 best_line_index = uint32.MaxValue;
        for (uint32 line_index = 0; line_index < layer.line_count; line_index++)
        {
            uint16 line_height = layer.line_heights[line_index];
            uint16 line_advance = layer.line_advances[line_index];
            uint16 horizontal_left_in_line = max_dim - line_advance;

            all_lines_height += line_height;

            bool can_use_line = true;
            if (line_height < height)
            {
                can_use_line = false;
            }
            if (horizontal_left_in_line < width)
            {
                can_use_line = false;
            }

            if (can_use_line)
            {
                if (best_line_index >= FONT_ATLAS_LAYER_MAX_LINES)
                {
                    // first acceptable line found
                    best_line_index = line_index;
                }
                else if (layer.line_heights[best_line_index] < line_height)
                {
                    // check if this line is better than current best line
                    best_line_index = line_index;
                }
            }
        }

        uint16 height_left = max_dim - all_lines_height;
        if (best_line_index < FONT_ATLAS_LAYER_MAX_LINES && height_left >= height)
        {
            // We have a line that can be used. But it's still possible to create a new line.
            // Let's check if we should create a new line - it's a heuristic that tries to minimize
            // avoid wasting space in lines that are too big for this glyph run.
            uint16 best_line_height = layer.line_heights[best_line_index];
            uint32 waste_px = best_line_height - height;
            float waste_share = waste_px / (float)best_line_height;

            // If layer is almost full the threshold for starting a new line is very big.
            float used_height_share = all_lines_height / (float)max_dim;
            float share_threshold = 0.2f + 0.8f * used_height_share;

            if (waste_px > 8 && waste_share > share_threshold)
            {
                best_line_index = FONT_ATLAS_LAYER_MAX_LINES;
            }
        }

        // if no best line - try to create a create new line
        if (best_line_index >= FONT_ATLAS_LAYER_MAX_LINES && height_left >= height)
        {
            if (layer.line_count < FONT_ATLAS_LAYER_MAX_LINES)
            {
                best_line_index = layer.line_count;
                layer.line_count += 1;

                layer.line_heights[best_line_index] = height;
            }
        }

        // We have best line line with free space - try to allocate a slot in hash table
        if (best_line_index < FONT_ATLAS_LAYER_MAX_LINES)
        {
            FontGlyph slot = this.FindGlyphInLayer(ref layer, hash, true);
            if (slot.hash == 0)
            {
                uint16 line_y_offset = 0;
                for (uint32 line_index = 0; line_index < best_line_index; line_index++)
                {
                    line_y_offset += layer.line_heights[line_index];
                }

                slot.hash = hash;
                slot.p = .(
                    layer.line_advances[best_line_index] + margin,
                    line_y_offset + margin,
                );
                slot.dim = .(
                    orig_width,
                    orig_height,
                );
                slot.layer = this.LayerIndexFromPointer(layer);

                layer.line_advances[best_line_index] += width;
                return slot;
            }
        }

        // Failed to allocate glyph run in this layer
        return .Err;
    }

    public uint8 LayerIndexFromPointer(FontLayer layer)
    {
        
        uint8 index = (uint8)(this.layers.IndexOf(layer) / sizeof(FontLayer));
        return index;
    }

    // Ovveride (new) this
    public FontGlyph? LoadGlyphFromFontFace(
        uint32 codepoint, uint8 font, uint16 pixel_height, uint16 margin)
    {
        return null;
    }

    public FontGlyph GetGlyph(
        GPU gpu, uint32 codepoint, uint8 preferred_font, uint16 pixel_height)
    {
        uint16 margin = FONT_ATLAS_MARGIN;
        uint16 margin2 = margin * 2;

        int hash = this.CodepointHash(codepoint, preferred_font, pixel_height);
        uint8 font = preferred_font;

        // Find already existing glyph run
        for (uint32 layer_offset = 0; layer_offset < this.layers.Count; layer_offset++)
        {
            uint8 layer_index = (uint8)(layer_offset + active_layer_index) % this.layers.Count;
            FontGlyph glyph_run = this.FindGlyphInLayer(ref this.layers[layer_index], hash, false);
            if (glyph_run.hash == hash)
            {
                return glyph_run;
            }
        }

        // Load and render glyph
        //glyph: *FT_GlyphSlotRec_;
        FontGlyph? glyph = null;

        for (uint32 font_fallback = 0; font_fallback < 2; font_fallback++)
        {
            if (glyph.HasValue)
            {
                break;
            }
            // TODO: If glyph wasn't found then choose something default

            glyph = this.LoadGlyphFromFontFace(codepoint, font, pixel_height, margin);
        }

        if (!glyph.HasValue)
        {
            Logger.Log("Can't find glyph_index in font {} (or fallbacks) for codepoint {}",
                scope String(preferred_font), scope String(codepoint), .INFO);
            return .{};
        }

        // Find glyph slot in atlas.
        // Look for glyph slot in existing atlas layers.
        Result<FontGlyph> slot = .Err;
        for (uint32 layer_offset = 0; layer_offset < this.layers.Count - 1; layer_offset++)
        {
            uint32 layer_index = (active_layer_index + layer_offset) % layers.Count;
            slot = this.CreateGlyphInLayer(
                ref this.layers[layer_index], hash, glyph.Value.dim[0], glyph.Value.dim[1]);
            if (slot case .Ok)
            {
                break;
            }
        }

        if (slot case .Err)
        // Couldn't find space in any layer. Clear the oldest layer to make space for new glyph.
        {
            // Advance active_layer index (backwards) and clear active layer.
            active_layer_index += layers.Count - 1;
            active_layer_index %= layers.Count;

            slot = this.CreateGlyphInLayer(ref layers[active_layer_index], hash,
                glyph.Value.dim[0], glyph.Value.dim[1]);
        }

        // Upload surface to GPU (if free slot was found).
        if (slot case .Ok(var resSlot))
        {
            // @speed Check if it makes sense to batch these transfers.
            SDL_GPUTransferBufferCreateInfo trans_cpu = SDL_GPUTransferBufferCreateInfo()
            {
                usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                size = (uint32)resSlot.pixels.Length * sizeof(uint32)
            };
            SDL_GPUTransferBuffer* buf_transfer = SDL_CreateGPUTransferBuffer(gpu.device, &trans_cpu);

            // CPU memory -> GPU memory
            {
                void* mapped_memory = SDL_MapGPUTransferBuffer(gpu.device, buf_transfer, false);
                Internal.MemCpy(mapped_memory, glyph.Value.pixels.Ptr, glyph.Value.pixels.Length);
                SDL_UnmapGPUTransferBuffer(gpu.device, buf_transfer);
            }

            // GPU memory -> GPU texture
            {
                SDL_GPUCommandBuffer* cmd = SDL_AcquireGPUCommandBuffer(gpu.device);
                SDL_GPUCopyPass* copy_pass = SDL_BeginGPUCopyPass(cmd);

                SDL_GPUTextureTransferInfo trans_gpu = SDL_GPUTextureTransferInfo()
                {
                    transfer_buffer = buf_transfer,
                    offset = 0
                };

                Debug.Assert(resSlot.p[0] >= margin);
                Debug.Assert(resSlot.p[1] >= margin);
                Debug.Assert(resSlot.p[0] + resSlot.dim[0] + margin <= this.texture_dim);
                Debug.Assert(resSlot.p[1] + resSlot.dim[1] + margin <= this.texture_dim);
                SDL_GPUTextureRegion dst_region = SDL_GPUTextureRegion()
                {
                    texture = gpu.ui.gpu_atlas_texture,
                    layer = resSlot.layer,
                    x = resSlot.p[0] - margin,
                    y = resSlot.p[1] - margin,
                    w = resSlot.dim[0] + margin2,
                    h = resSlot.dim[1] + margin2,
                    d = 1
                };
                SDL_UploadToGPUTexture(copy_pass, &trans_gpu, &dst_region, false);

                SDL_EndGPUCopyPass(copy_pass);
                SDL_SubmitGPUCommandBuffer(cmd);
            }

            SDL_ReleaseGPUTransferBuffer(gpu.device, buf_transfer);
            }

            return resSlot;
        }

}
