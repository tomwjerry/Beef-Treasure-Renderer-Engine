namespace Treasure.Renderer;
using System;
using System.Collections;
using SDL3;
using Treasure;
using Treasure.Util;

struct WorldVertex
{
    public Vector3f p;
    public Vector3f normal;
    public Vector2f uv;
    public uint32 joints_packed4;
    public Vector4f joint_weights;
}

enum ShaderFlags : uint32, IHashable // @todo generate hlsl header for shaders out of this
{
    case Nothing;
    case DoMeshSkinning;
    case UseInstanceBuffer;
    case SampleTexDiffuse;
    case SampleTexNormal;
    case SampleTexRoughness;
    case ApplyShadows;
    case DrawBorderAtUVEdge;
    case PixelEarlyExit;

    public int GetHashCode()
    {
        return (int)this;
    }
}

enum WorldDir : uint32
{
    E, // +X
    W, // -X
    N, // +Y
    S, // -Y
    T, // +Z
    B, // -Z
    COUNT
}

struct WorldUniform : IHashable
{
    public Mat4 camera_transform;
    public Mat4 shadow_transform;
    public Vector3f camera_position;
    public Vector3f sun_dir;
    public ShaderFlags flags;

    public Color32 fog_color; // RGBA
    public Color32 sky_ambient; // RGBA
    public Color32 sun_diffuse; // RGBA
    public Color32 sun_specular; // RGBA

    public Color32 material_diffuse; // RGBA
    public Color32 material_specular; // RGBA
    public float material_roughness;
    public float material_loaded_t;

    public int GetHashCode()
    {
        return (int)camera_transform.GetHashCode() +
            (int)shadow_transform.GetHashCode() +
            (int)camera_position.GetHashCode() +
            (int)sun_dir.GetHashCode() +
            (int)flags.GetHashCode() +
            (int)fog_color.GetHashCode() +
            (int)sky_ambient.GetHashCode() +
            (int)sun_diffuse.GetHashCode() +
            (int)sun_specular.GetHashCode() +
            (int)material_diffuse.GetHashCode() +
            (int)material_specular.GetHashCode() +
            (int)material_roughness.GetHashCode() +
            (int)material_loaded_t.GetHashCode();
    }
}

struct WorldInstanceModel
{
    public Mat4 transform;
    public Color32 color;
    public Color32 picking_color;
    public uint32 pose_offset; // in indices; unused for rigid
}

class World
{
    public ASSETState assetState;
    public GPUBATCHState batchState;

    public void ApplyMaterialToUniform(ref WorldUniform uniform,
        Material material, bool simplified_pipeline)
    {
        uniform.material_loaded_t = material.stream.loaded_t;
        uniform.material_diffuse = (Color32)material.matparams.diffuse;
        uniform.material_specular = (Color32)material.matparams.specular;
        uniform.material_roughness = material.matparams.roughness;

        uniform.flags = .ApplyShadows;

        if (simplified_pipeline)
        {
            uniform.flags |= .PixelEarlyExit;
        }

        if (material.has_texture)
        {
            if (material.texture_layers >= 1) { uniform.flags |= .SampleTexDiffuse; }
            if (material.texture_layers >= 2) { uniform.flags |= .SampleTexNormal; }
            if (material.texture_layers >= 3) { uniform.flags |= .SampleTexRoughness; }
        }
    }

    public void DrawModel(SDL_GPUDevice* device, MODELKey model_key, Mat4 transform,
        Span<AnimationTrack> animation_tracks,
        Color32 color, Color32 picking_color = 0)
    {
        WorldInstanceModel instance = WorldInstanceModel()
        {
            transform = transform,
            color = color,
            picking_color = picking_color
        };

        Model model;
        this.assetState.GetModel(model_key, out model);
        if (model.is_skinned)
        {
            Span<GPUBatch> instance_batch;
            batchState.GetPosesBatch(out instance_batch);
            instance.pose_offset = (uint32)instance_batch.Length;

            Span<Mat4> transforms = model.animationState.GetPoseTransforms(model.skeleton, animation_tracks);
            uint32 transfer_size = (uint32)transforms.Length * sizeof(Mat4);
            this.batchState.TransferUploadBytes(device, instance_batch[0],
                (void*)&transforms, transfer_size, (uint32)transforms.Length);
        }

        GPUBatch instance_batch;
        this.batchState.FindOrCreateBundle(.(){ type = .ModelInstances, model_key = model_key }, out instance_batch);
        this.batchState.TransferUploadBytes(device, instance_batch, (void*)&instance, sizeof(WorldInstanceModel), 1);
    }

    public void DrawVertices(SDL_GPUDevice* device, MATERIALKey material, Span<WorldVertex> vertices)
    {
        GPUBatch mesh_batch;
        this.batchState.FindOrCreateBundle(.(){ type=.MeshVertices, material_key=material }, out mesh_batch);
        uint32 transfer_size = (uint32)vertices.Length * sizeof(WorldVertex);
        this.batchState.TransferUploadBytes(device, mesh_batch, vertices.Ptr, transfer_size, (uint32)vertices.Length);
    }

    public void DrawObjects(SDL_GPUDevice* device, Span<RendererObject> objects)
    {
      for (let obj in objects)
      {
          Vector3f pos = obj.p;
          Mat4 transform = Mat4.TranslationMatrix(pos);
          
          ColorV4 objcolor = ColorV4(){ X = 1, Y = 1, Z = 1, W = 1 };
    
          this.DrawModel(device, obj.model, transform, obj.animation_tracks,
            Color32.Color32_RGBAf(objcolor), 0);
        }
      }
}
