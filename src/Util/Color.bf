namespace Treasure.Util;
using System;

struct ColorV4 : Vector4f
{
    public static ColorV4 ColorV4_32(Color32 packed)
    {
        float inv = 1.0f / 255.0f;
        ColorV4 res = ColorV4();
        res.X = ((uint32)packed & 255) * inv;
        res.Y = (((uint32)packed >> 8) & 255) * inv;
        res.Z = (((uint32)packed >> 16) & 255) * inv;
        res.W = (((uint32)packed >> 24) & 255) * inv;
        return res;
    }
}

struct Color32 : uint32, IHashable
{
    public static Color32 Color32_RGBAi(uint32 r, uint32 g, uint32 b, uint32 a)
    {
        Color32 res = ((a << 24) |
            (b << 16) |
            (g << 8) |
            r);
        return res;
    }

    public static Color32 Color32_RGBi(uint32 r, uint32 g, uint32 b)
    {
        return Color32_RGBAi(r, g, b, 255);
    }
    public static Color32 Color32_Grayi(uint32 rgb)
    {
        return Color32_RGBi(rgb, rgb, rgb);
    }

    public static Color32 Color32_SetAlphai(Color32 color, uint32 a)
    {
        Color32 no_alpha = (uint32)color & ~(0xff << 24);
        return (no_alpha | (a << 24));
    }

    public static Color32 Color32_RGBAf(float r, float g, float b, float a)
    {
        uint32 ri = ((uint32)r * 255) & 255;
        uint32 gi = ((uint32)g * 255) & 255;
        uint32 bi = ((uint32)b * 255) & 255;
        uint32 ai = ((uint32)a * 255) & 255;
        return Color32_RGBAi(ri, gi, bi, ai);
    }

    public static Color32 Color32_RGBf(float r, float g, float b)
    {
        uint32 ri = ((uint32)r * 255) & 255;
        uint32 gi = ((uint32)g * 255) & 255;
        uint32 bi = ((uint32)b * 255) & 255;
        return Color32_RGBAi(ri, gi, bi, 255);
    }

    public static Color32 Color32_Grayf(float rgb)
    {
        return Color32_RGBf(rgb, rgb, rgb);
    }
    public static Color32 Color32_RGBf(Vector3f color)
    {
        return Color32_RGBf(color.X, color.Y, color.Z);
    }
    public static Color32 Color32_RGBf(float[3] color)
    {
        return Color32_RGBf(color[0], color[1], color[2]);
        }
    public static Color32 Color32_RGBAf(Vector4f color)
    {
        return Color32_RGBAf(color.X, color.Y, color.Z, color.W);
    }
    public static Color32 Color32_RGBAf(float[4] color)
    {
        return Color32_RGBAf(color[0], color[1], color[2], color[3]);
    }

    public static Color32 Lerp(Color32 c0, Color32 c1, float t)
    {
        // @todo Do a lerp in a different color space - like Oklab or something
        // https://raphlinus.github.io/color/2021/01/18/oklab-critique.html
        ColorV4 vec0 = ColorV4.ColorV4_32(c0);
        ColorV4 vec1 = ColorV4.ColorV4_32(c1);
        Vector4f lerped = Vector4f.Lerp(vec0, vec1, t);
        Color32 res = Color32_RGBAf(lerped);
        return res;
    }

    public int GetHashCode()
    {
        return (int)this;
    }
}
