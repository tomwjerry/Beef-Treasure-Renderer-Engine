namespace Treasure.Renderer;
using System;
using System.Diagnostics;
using System.Collections;
using Treasure;
using Treasure.Util;

struct Animation
{
    public String name;
    public float t_min;
    public float t_max;
    public List<AnimationChannel> channels;
}

//
//
//
enum AnimationAdvanceMode
{
    TIME,
    DISTANCE,
    MANUAL01,
    MANUAL
}

struct AnimationRecord
{
    public int32 animation_index;
    public List<float> joint_weights; // Animations like punching shouldn't really apply to legs etc
    // count = 0 -> all weights are equal to one
}

struct AnimationRequest
{
    public uint64 start; // @todo use type like ServerTick here; And add functions like TimeElapsedFromServerTick(tick)
    public uint16 type;
}

struct AnimationTrack
{
    public uint16 type;
    public float t;
    public float weight;
    public AnimationAdvanceMode anim_mode;
}

struct DesiredAnimation
{
    public uint16 type;
    public String animationName;
    public Span<(String, float)> joints;
}

enum AnimationWaterfallType
{
    MULTIPLY,
    ASSIGN
}

class AnimationState
{
    public List<AnimationRecord> records; // @todo should be attached to skeleton, yes or yes?

    public AnimationRecord RecordFromType(uint16 type)
    {
        return this.records[type];
    }

    public Animation FromType(Skeleton skeleton, uint16 type)
    {
        return skeleton.animations[this.RecordFromType(type).animation_index];
    }

    public void Init(Skeleton skeleton, Span<DesiredAnimation> desired_animations)
    {
        for (let it in desired_animations)
        {
            List<float> temp_weights = scope List<float>(skeleton.joints_count);
            for (var t in temp_weights)
            {
                t = 1.0f;
            }

            records[it.type].animation_index = this.AnimationNameToIndex(skeleton, it.animationName).Value;

            for (let joint in it.joints)
            {
                this.WaterfallToChildren<float>(.ASSIGN, skeleton,
                    this.JointNameToIndex(skeleton, joint.0).Value, temp_weights, joint.1);
            }

            bool has_non_one = false;
            for (let tw in temp_weights)
            {
                if (tw != 1.0)
                {
                    has_non_one = true;
                    break;
                }
            }
            if (has_non_one)
            {
                records[it.type].joint_weights = temp_weights;
            }
        }
    }

    public void AnimateObjects(
        Span<RendererObject> objects, ASSETState assetState, float dt)
    {
        for (let obj in objects)
        {
            Model model;
            assetState.GetModel(obj.model, out model);
            if (model.is_skinned)
            {
                // Fill animation tracks
                bool all_joints_are_masked = false;
                for (int it = 0; it < obj.animation_tracks.Count; it++)
                {
                    if (all_joints_are_masked)
                    {
                        obj.animation_tracks[it].weight = 0.0f;
                    }

                    // Advance T
                    if (obj.animation_tracks[it].anim_mode == .DISTANCE)
                    {
                        Animation anim = this.FromType(model.skeleton, obj.animation_tracks[it].type);
                        float dist_t =
                            (anim.t_max - anim.t_min) * obj.animation_distance01 + anim.t_min;
                        obj.animation_tracks[it].t = this.WrapTime(model.skeleton, obj.animation_tracks[it].type, dist_t);
                    }
                    else if (obj.animation_tracks[it].anim_mode == .TIME)
                    {
                        obj.animation_tracks[it].t += dt;
                        obj.animation_tracks[it].t = this.WrapTime(model.skeleton,
                            obj.animation_tracks[it].type, obj.animation_tracks[it].t);
                    }
                    else if (obj.animation_tracks[it].anim_mode == .MANUAL01)
                    {
                        Animation anim = this.FromType(model.skeleton, obj.animation_tracks[it].type);
                        obj.animation_tracks[it].t =
                            (anim.t_max - anim.t_min) * obj.animation_tracks[it].t + anim.t_min;
                    }


                    AnimationRecord record = this.RecordFromType(obj.animation_tracks[it].type);
                    if (record.joint_weights.Count == 0 &&
                        obj.animation_tracks[it].weight == 1.0f)
                    {
                        all_joints_are_masked = true;
                    }
                }
            }
        }
    }

    public Span<Mat4> GetPoseTransforms(Skeleton skeleton, Span<AnimationTrack> tparams)
    {
        Span<Vector3f> accumulated_scales = skeleton.bind_scales;
        Span<Quat> accumulated_rotations = skeleton.bind_rotations;
        Span<Vector3f> accumulated_translations = skeleton.bind_translations;

        // mix default rest pose + animation channels using temporary memory
        for (int param_index = 0; param_index < tparams.Length; param_index++)
        {
            if (tparams[param_index].weight <= 0)
            {
                continue;
            }

            Span<Vector3f> scales;
            Span<Quat> rotations;
            Span<Vector3f> translations;

            if (param_index == 0)
            {
                scales = accumulated_scales;
                rotations = accumulated_rotations;
                translations = accumulated_translations;
            }
            else
            {
                scales = skeleton.bind_scales;
                rotations = skeleton.bind_rotations;
                translations = skeleton.bind_translations;
            }

            AnimationRecord record = this.RecordFromType(tparams[param_index].type);

            // Overwrite translations, rotations, scales with values from animation
            {
                Animation anim = skeleton.animations[record.animation_index];
                float time = Math.Clamp(tparams[param_index].t, anim.t_min, anim.t_max);

                for (let channel in anim.channels)
                {
                    if (channel.joint_index >= skeleton.joints_count)
                    {
                        Debug.Assert(false);
                        continue;
                    }

                    if (record.joint_weights.Count > 0 &&
                        record.joint_weights[channel.joint_index] <= 0.0)
                    {
                        continue;
                    }

                    float t = 1.0f;
                    uint32 sample_start = 0;
                    uint32 sample_end = 0;
                    // find t, sample_start, sample_end
                    {
                        // @speed binary search might be faster?
                        for (uint32 it_index = 0; it_index < channel.inputs.Count; it_index++)
                        {
                            if (channel.inputs[it_index] >= time)
                            {
                                break;
                            }
                            sample_start = it_index;
                        }

                        sample_end = sample_start + 1;
                        if (sample_end >= channel.inputs.Count)
                        {
                            sample_end = sample_start;
                        }

                        float time_start = channel.inputs[sample_start];
                        float time_end = channel.inputs[sample_end];

                        if (time_start < time_end)
                        {
                            float time_range = time_end - time_start;
                            t = (time - time_start) / time_range;
                        }
                    }

                    if (channel.type == .Rotation)
                    {
                        Quat q0 = Quat(channel.outputs[sample_start],
                            channel.outputs[sample_start + 1],
                            channel.outputs[sample_start + 2],
                            channel.outputs[sample_start + 3]);
                        Quat q1 = Quat(channel.outputs[sample_end],
                            channel.outputs[sample_end + 1],
                            channel.outputs[sample_end + 2],
                            channel.outputs[sample_end + 3]);
                        Quat value = Quat.Slerp(q0, q1, t); // @todo NLerp with "neighborhood operator" could be used here?

                        rotations[channel.joint_index] = value;
                    }
                    else
                    {
                        Vector3f v0 = Vector3f(channel.outputs[sample_start],
                            channel.outputs[sample_start + 1],
                            channel.outputs[sample_start + 2]);
                        Vector3f v1 = Vector3f(channel.outputs[sample_end],
                            channel.outputs[sample_end + 1],
                            channel.outputs[sample_end + 2]);
                        Vector3f value = Vector3f.Lerp(v0, v1, t);

                        if (channel.type == .Translation)
                        {
                            translations[channel.joint_index] = value;
                        }
                        else
                        {
                            scales[channel.joint_index] = value;
                        }
                    }
                }
            }

            if (param_index > 0)
            {
                for (int joint_index = 0; joint_index < skeleton.joints_count; joint_index++)
                {
                    float joint_weight = 1.0f;
                    if (record.joint_weights.Count > 0)
                    {
                        joint_weight = record.joint_weights[joint_index];
                    }

                    float weight = tparams[param_index].weight * joint_weight;
                    if (weight <= 0) { continue; }

                    accumulated_scales[joint_index] =
                        Vector3f.Lerp(accumulated_scales[joint_index], scales[joint_index], weight);
                    accumulated_rotations[joint_index] =
                        Quat.Slerp(accumulated_rotations[joint_index], rotations[joint_index],weight);
                    accumulated_translations[joint_index] =
                        Vector3f.Lerp(
                            accumulated_translations[joint_index], translations[joint_index], weight);
                }
            }
        }

        List<Mat4> result_matrices = scope List<Mat4>(skeleton.joints_count);
        for (int it_index = 0; it_index < skeleton.joints_count; it_index++)
        {
            Mat4 scale = Mat4.ScaleMatrix(accumulated_scales[it_index]);
            Mat4 rot =  Mat4.RotationMatrix(accumulated_rotations[it_index]);
            Mat4 trans =  Mat4.TranslationMatrix(accumulated_translations[it_index]);
            result_matrices[it_index] = trans * (rot * scale);
        }

        this.WaterfallToChildren(.MULTIPLY, skeleton, 0, result_matrices, skeleton.root_transform);

        for (int it_index = 0; it_index < skeleton.joints_count; it_index++)
        {
            result_matrices[it_index] =
            result_matrices[it_index] * skeleton.inverse_matrices[it_index];
        }

        return result_matrices;
    }

    public float WrapTime(Skeleton skeleton, int32 anim_index, float itime)
    {
        float time = itime;
        if (anim_index < skeleton.animations.Count)
        {
            Animation anim = skeleton.animations[anim_index];
            time = WrapFloat(anim.t_min, anim.t_max, time);
        }
        else
        {
            time = 0;
        }
        return time;
    }
    public float WrapTime(Skeleton skeleton, int16 type, float time)
    {
        return WrapTime(skeleton, this.records[type].animation_index, time);
    }

    public void WaterfallToChildren<T>(AnimationWaterfallType mode,
        Skeleton skeleton, uint32 joint_index, Span<T> values, T parent_value) where T : operator T * T
    {
        // This function traverses skeleton joint hierarchy from root joint to children.

        if (joint_index >= skeleton.joints_count)
        {
            Debug.Assert(false);
            return;
        }

        switch (mode)
        {
            case .MULTIPLY:
                values[joint_index] = parent_value * values[joint_index];
                break;
            case .ASSIGN:
                values[joint_index] = parent_value;
                break;
        }

        Range<UInt32> child_range = skeleton.child_index_ranges[joint_index];
        for (uint32 it = (uint32)child_range.Start; it < (uint32)child_range.End; it++)
        {
            if (it >= skeleton.joints_count)
            {
                Debug.Assert(false);
                return;
            }

            uint32 child_joint_index = skeleton.child_index_buffer[it];
            this.WaterfallToChildren(mode, skeleton,
                child_joint_index, values, values[joint_index]);
        }
    }

    //
    //
    //
    public Result<int32> AnimationNameToIndex(Skeleton skeleton, String name)
    {
        for (int32 it_index = 0; it_index < skeleton.animations.Count; it_index++)
        {
            if (name == skeleton.animations[it_index].name)
            {
                return .Ok(it_index);
            }
        }
        Logger.Log("Animation name not found: %", name, .WARN);
        return .Err;
    }

    public Result<uint32> JointNameToIndex(Skeleton skeleton, String name)
    {
        for (uint32 it_index = 0; it_index < skeleton.joint_names.Count; it_index++)
        {
            if (name == skeleton.joint_names[it_index])
            {
                return .Ok(it_index);
            }
        }
        Logger.Log("Joint name not found: %", name, .WARN);
        return .Err;
    }
}