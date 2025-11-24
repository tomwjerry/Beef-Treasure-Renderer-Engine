namespace Treasure;
using System.Collections;
using Treasure.Renderer;
using Treasure.Util;

struct RendererObjectKey
{
    public uint16 index;
    public uint16 serial_number;
}

enum RendererObjectFlags : uint32
{
    ANIMATE_TRACKS,
    DRAW_MODEL
}

struct RendererObject
{
    public RendererObjectKey key;
    public RendererObjectFlags flags;
    public bool init;
    public Vector3f p; // XY center, Z at bottom
    
    public Queue<AnimationRequest> animation_requests; 

    // visuals
    public Color32 color; // unused?
    public Quat rotation;
    public MODELKey model; // used by DrawModel
    public MATERIALKey material; // used by DrawCollision
    public float height; // used by DrawCollision
    public float texture_texels_per_m; // used by DrawCollision

    public Quat animated_rot; // animates towards rotation
    public Vector3f animated_p; // animates towards (V3){p.x, p.y, p.z}

    public int32 overwrite_animation_index = -1; // debug tool
    public AnimationAdvanceMode overwrite_animation_mode;

    public float animation_distance01; // in range [0; 1]
    public bool animation_attack_hide_cooldown;
    // animation_requests_hot_t: [3] float;
    public List<AnimationTrack> animation_tracks;
}
