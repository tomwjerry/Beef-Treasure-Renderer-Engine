namespace Treasure.Renderer;
using SDL3;
using System;
using Treasure.Util;

struct UIUniform : IHashable
{
    public Vector2f window_dim;
    public Vector2f texture_dim;

    public int GetHashCode()
    {
        return (int)window_dim.GetHashCode() +
            (int)texture_dim.GetHashCode();
    }
}

typealias UIClip = Rect;

struct UIShape
{
    public Rect rect;
    public Rect tex_rect;
    public float tex_layer = -1.0f;
    public float corner_radius;
    public float edge_softness;
    public float border_thickness;
    public Color32 color; // @todo array of 4 colors for gradients
}

struct UIShapeIn3D
{
    public Vector3f world_p;
    public UIShape shape;
}

class UIRenderer
{
    public Rect UI_Clip;
    private Application app;

    public SDL_GPUTexture* gpu_atlas_texture;
    public SDL_GPUSampler* gpu_atlas_sampler;
    public SDL_GPUBuffer* gpu_indices;
    public SDL_GPUBuffer* gpu_shape_buffer;
    public SDL_GPUBuffer* gpu_clip_buffer;
    // @todo move some of these things to game_render_ui and use GPU_BATCH?
    public uint32[1024 * 8] indices;
    public uint32 indices_count;

    public UIShape[1024 * 2] shapes;
    public uint32 shapes_count;

    public UIShapeIn3D[1024 * 2] shapes3d;
    public uint32 shapes3d_count;
    public UIClip[1024] clips; // buffer that's uploaded to GPU
    public uint32 clips_count;
    public uint32[256] clip_stack; // contains indices into clips; tracks state when UI is constructed @todo remove in the future
    public uint32 clip_stack_index;

    public Font font;

    public void AddShape(UIShape shape)
    {
        shapes[shapes_count] = shape;
        shapes_count += 1;
    }

    public void AddIndices(params uint32[] ilist)
    {
        for (let ind in ilist)
        {
            indices[indices_count] = ind;
            indices_count += 1;
        }
    }

    public void Add3DShape(Vector3f world_p, UIShape shape)
    {
        shapes3d[shapes3d_count] = UIShapeIn3D() {
            world_p = world_p, shape = shape
        };
        shapes3d_count += 1;
    }

    public void AddClip(UIClip clip)
    {
        uint32 clip_index = clips_count;

        clips_count += 1;
        clips[clip_index] = clip;

        clip_stack_index += 1;
        clip_stack[clip_stack_index] = clip_index;
    }

    public void PopClip()
    {
        if (clip_stack_index == 0)
        {
            return;
        }
        clip_stack_index -= 1;
    }

    public void ClearIndices()
    {
        indices_count = 0;
    }
    public void ClearShapes()
    {
        shapes_count = 0;
    }
    public void ClearShapes3D()
    {
        shapes3d_count = 0;
    }
    public void ClearClips()
    {
        clips[0] = UIClip(.(0, 0), .(float.MaxValue, float.MaxValue));
        clips_count = 1;
        clip_stack[0] = 0;
        clip_stack_index = 0;
    }

    public this(Application inapp)
    {
        app = inapp;
    }

    public void UIDraw2D(UIShape shape)
    {
        if (this.indices_count + 6 > this.indices.Count)
        {
            return; // @todo log errors?
        }
        if (this.shapes_count + 6 > this.shapes.Count)
        {
            return; // @todo log errors?
        }

        uint32 clip_i = UIActiveClipIndex();

        uint32 shape_i = this.shapes_count;
        this.AddShape(shape);

        uint32 encoded = ((shape_i << 2) | (clip_i << 18));
        this.AddIndices(0 | encoded, 1 | encoded, 2 | encoded,
            2 | encoded, 1 | encoded, 3 | encoded);
    }

    public void UIDraw3D(Vector3f world_p, UIShape shape)
    {
        if (this.shapes3d_count + 1 > this.shapes3d.Count)
        {
            return; // @todo log errors?
        }
        
        this.Add3DShape(world_p, shape);
    }

    public uint32 UIActiveClipIndex()
    {
        uint32 clip_index = this.clip_stack[this.clip_stack_index];
        return clip_index;
    }

    public UIClip UIActiveClip()
    {
        return this.clips[UIActiveClipIndex()];
    }

    public void UIPushClip(UIClip clip_)
    {
        if (this.clip_stack_index + 1 >= this.clip_stack.Count)
        {
            return; // @todo increase clip_stack so PopClip does correct thing; fallback to no clip
        }
        if (this.clips_count >= this.clips.Count)
        {
            return;
        }

        UIClip clip = clip_.Intersection(UIActiveClip());
        this.AddClip(clip);
    }

    public void UIPopClip()
    {
        this.PopClip();
    }

    public void UITranslate3DShapes()
    {
        for (int it = 0; it < this.shapes3d_count; it++)
        {
            Vector3f world_p = this.shapes3d[it].world_p;
            UIShape shape = this.shapes3d[it].shape;

            Vector4f transformed_p = app.mainCamera.camera_transform *
                Vector4f(world_p.X, world_p.Y, world_p.Z, 1.0f);
            Vector4f divided_p = Vector4f(transformed_p.X, transformed_p.Y, transformed_p.Z, 0.0f) / transformed_p.W;
            Vector2f flipped_p = Vector2f(divided_p.X, -divided_p.Y);
            Vector2f screen_p = (flipped_p + .(1.0f, 1.0f)) *
                (.(app.window_dim[0], app.window_dim[1]) * 0.5f);

            shape.rect.Min += screen_p;
            shape.rect.Max += screen_p;
            UIDraw2D(shape);
        }
    }

    public void UI_ClearRenderCounters()
    {
        this.ClearIndices();
        this.ClearShapes();
        this.ClearShapes3D();
        this.ClearClips();
    }
}
