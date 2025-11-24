namespace Treasure;
using SDL3;
using System;
using System.Collections;
using System.Threading;
using Treasure;
using Treasure.Renderer;
using Treasure.Util;

class ASSETState
{
    private append BumpAllocator arena = .(); 

    // Materials
    public Material nil_material;
    public List<Material> materials;

    // Texture loading thread
    public bool tex_load_needed;
    public Monitor tex_semaphore;
    public Thread tex_thread;

    // Models
    public Model nil_model;
    public List<Model> models;
    public SDL_GPUBuffer* model_vertices;
    public SDL_GPUBuffer* model_indices;
    public List<Skeleton> skeletons;

    // Blobs
    public List<String> shaders;
    public List<String> fonts;
    public List<String> sounds;

    public void GetMaterial(MATERIALKey key, int64 frame_number, out Material asset)
    {
        // @speed hash table lookup in the future
        asset = nil_material;
        for (let it in this.materials)
        {
            if (it.key.Match(key))
            {
                asset = it;
                break;
            }
        }

        if (!asset.MaterialIsNil())
        {
            asset.stream.last_touched_frame = frame_number;
            if (!asset.stream.flags.HasFlag(.LOADED))
            {
                this.tex_load_needed = true;
            }
        }
    }

    public void GetModel(MODELKey key, out Model asset)
    {
        // @speed hash table lookup in the future
        asset = nil_model;
        for (let it in this.models)
        {
            if (it.key.Match(key))
            {
                asset = it;
                break;
            }
        }
    }

    // Shader
    public void GetShader(ShaderType type, out String shader)
    {
        if ((int)type >= this.shaders.Count)
        {
            shader = "";
            return;
        }
        shader = this.shaders[(int)type];
    }
}

enum ShaderType
{
    WORLD_VS,
    WORLD_PS,
    UI_VS,
    UI_PS
}

enum ASSETType
{
    Material,
    Model
}

struct ASSETKey
{
    public uint64 type4_hash60;
    public String name;

    // material name format:
    //   tex.Bricks071
    //   Tree.Bark_diffuse

    public this(ASSETType type, String name/* EXTERNALLY OWNED STRING */) 
    {
        uint64 hash = (uint64)type.Underlying.GetHashCode();

        this.type4_hash60 = (uint64)type | (hash << 4);
        this.name = name;
    }

    public bool Match(ASSETKey b)
    {
        return this.type4_hash60 == b.type4_hash60;
    }

    public ASSETType KeyType()
    {
        return (ASSETType)(this.type4_hash60 & 0b1111);
    }

    public bool IsZeroKey()
    {
        return this.type4_hash60 == 0;
    }
}

struct MATERIALKey : ASSETKey
{
    public this(String name/* EXTERNALLY OWNED STRING */) : base(ASSETType.Material, name)
    {
    }
}

struct MODELKey : ASSETKey
{
    public this(String name/* EXTERNALLY OWNED STRING */) : base(ASSETType.Model, name)
    {
    }
}

struct ASSETStreamable
{
    public int64 last_touched_frame;
    public float loaded_t;
    public Flags flags;

    public enum Flags
    {
        ERROR,
        LOADED
    }
}

struct Texture
{
    public TexFormat format;
    public int32 width;
    public int32 height;
    public int32 lods;
    public int32 layers;
    public List<uint8> full_data;
    public List<MaterialTexSection> sections;
}

struct Material
{
    public ASSETStreamable stream;
    public MATERIALKey key;

    public MaterialParams matparams;
    public bool has_texture;
    public int texture_layers;
    public SDL_GPUTexture* stex;
    public bool isNil;

    public String name;
    public Texture ttex;
    public ShaderFlags shaderFlags;
    
    public bool MaterialIsNil()
    {
        return this.isNil;
    }
}

struct Mesh
{
    public MATERIALKey material;
    public uint vertices_start_index;
    public uint indices_start_index;
    public uint indices_count;
    public uint material_index;
}

struct Model
{
    public MODELKey key;
    public bool is_skinned;
    public Skeleton skeleton; // can be null
    public AnimationState animationState;
    public List<Mesh> meshes;
    public bool isNil;
    public String name;

    // Model
    public bool ModelIsNil()
    {
        return this.isNil;
    }
}

enum AnimationChannelType : uint32
{
    Translation,
    Rotation,
    Scale
}

struct AnimationChannel
{
    public AnimationChannelType type;
    public uint32 joint_index;
    public uint32 joint_index30_type2;  // [u32 | (PIE_AnimationChannelType << 30)] // @todo this is silly, simplify
    public List<float> inputs;  // float * count
    public List<float> outputs; // float * (3 or 4 [V3 or Quat]) * count
    // .count = inputs.count * (ifx type == .Rotation then 4 else 3);
}

struct Skeleton
{
    // each of these has the same count of elements (joints_count)
    public List<Mat4> inverse_matrices;
    public List<uint32> child_index_buffer; // @todo use u16 here?
    public List<Range<UInt32>> child_index_ranges; // @todo use u16 here?
    public List<Vector3f> translations;
    public List<Quat> rotations;
    public List<Vector3f> scales;
    public List<Range<UInt32>> name_ranges; // offset of min & max char* - can be transformed to S8
    public List<Animation> animations;
    public Mat4 root_transform;

    public uint32 joints_count; // all arrays below have count equal to joints_count
    public List<String> joint_names;

    public List<Vector3f> bind_translations;
    public List<Quat> bind_rotations;
    public List<Vector3f> bind_scales;
}

struct MaterialTexSection
{
    public uint32 width;
    public uint32 height;
    public uint32 lod;
    public uint32 layer;
    // relative to full_data of Material
    public uint32 data_offset;
    public uint32 data_size;
}

enum TexFormat : uint32
{
    Empty,
    R8G8B8A8,
    BC7_RGBA
}

enum MaterialFlags : uint32
{
    HasAlpha
}

struct MaterialParams
{
    public MaterialFlags flags;
    public uint32 diffuse;
    public uint32 specular;
    public float roughness; // [0:1]
}
