namespace Treasure.Optional;
using System;
using System.Collections;
using FreeType;
using Treasure;
using Treasure.Renderer;
using Treasure.UI;
using Treasure.Util;

class FreetypeFont : Font
{
    public FreeType.FT_Library ft_library;
    public List<FreeType.FT_Face> ft_faces;

    public this(Span<StringView> names, GPU gpu)
    {
        if (this.err != 0)
        {
            return;
        }

        this.err = FreeType.FT_Init_FreeType(this.ft_library);
        for (let it in names)
        {
            if (this.err != 0)
            {
                break;
            }

            this.err = FreeType.FT_Face(
                ft_library, it, 0, &ft_faces[it]);
        }

        this.MaybeResizeAtlasTexture(gpu);
    }

    public new FaceMetrics GetFaceMetrics(uint8 fontFam, uint16 pixel_height)
    {
        FreeType.FT_Face ft_face = this.ft_faces[font];
        FreeType.FT_Set_Pixel_Sizes(ft_face, 0, pixel_height);

        FaceMetrics result = FaceMetrics()
        {
            ascent = ft_face.size.metrics.ascender / 64.0f,
            descent = ft_face.size.metrics.descender / 64.0f,
            linespace = ft_face.size.metrics.height / 64.0f
        };
        return result;
    }

    public new FontGlyph LoadGlyphFromFontFace(
        uint32 codepoint, uint8 font, uint16 pixel_height, uint16 margin)
    {
        uint16 margin2 = margin * 2;
        FreeType.FT_Face ft_face = ft_faces[font];
        FreeType.FT_Set_Pixel_Sizes(ft_face, 0, pixel_height);
        uint16 glyph_index =  FreeType.FT_Get_Char_Index(ft_face, codepoint);
        if (glyph_index == 0)
        {
            return .();
        }

        FreeType.FT_Load_Glyph(ft_face, glyph_index, FreeType.FT_LOAD_COLOR);
        FreeType.FT_Render_Glyph(ft_face.glyph, .FT_RENDER_MODE_NORMAL);

        uint32[2] bitmap_dim = .(ft_face.glyph.bitmap.width, ft_face.glyph.bitmap.rows);
        if (bitmap_dim[0] > 0 && bitmap_dim[1] > 0)
        {
            uint32[2] bitmap_and_margin_dim = bitmap_dim;
            bitmap_and_margin_dim[0] += margin2;
            bitmap_and_margin_dim[1] += margin2;

            // Reject surfaces that are too big
            if (bitmap_and_margin_dim[0] > texture_dim || bitmap_and_margin_dim[1] > texture_dim)
            {
                return .();
            }

            // Copy bitmap into a new buffer in a correct format (RGBA) with margin
            uint32 glyph_pixels_size = bitmap_and_margin_dim[0] * bitmap_and_margin_dim[1] * 4;
            List<uint32> glyph_pixels = scope List<uint32>(glyph_pixels_size);

            for (int i = 0; i < glyph_pixels_size; i++)
            {
                glyph_pixels[i] = 0; // clear margin
            }

            if (ft_face.glyph.bitmap.pixel_mode == Freetype.FT_Pixel_Mode_.GRAY)
            {
                uint32 glyph_pixels_no_margin =
                    bitmap_and_margin_dim[0] /*skip margin rows*/ +
                    margin /*skip margin columns*/;
                for (uint32 y = 0; y < bitmap_dim[1]; y++)
                {
                    uint8 bitmap_row = ft_face.glyph.bitmap.buffer[
                        ft_face.glyph.bitmap.pitch * y];
                    uint32 glyph_row = glyph_pixels_no_margin + bitmap_and_margin_dim[0] * y;
                    for (int x = 0; x < bitmap_dim[0]; x++)
                    {
                        glyph_pixels[glyph_row + x] =
                            (uint32)Color32.Color32_RGBAi(255, 255, 255, glyph_pixels[glyph_row + x]);
                    }
                }
            }
            else
            {
                Logger.Log("Unsupported bitmap pixel_mode coming from freetype: {}\n",
                    scope String(ft_face.glyph.bitmap.pixel_mode), .WARN);
                return .{};
            }

            // Fill glyph metrics
            FontGlyph result = FontGlyph()
            {
                bearing = Vector2f(
                    ft_face.glyph.metrics.horiBearingX / 64.0f,
                    ft_face.glyph.metrics.horiBearingY / -64.0f
                ),
                advance = ft_face.glyph.metrics.horiAdvance / 64.0f,
            };
    
            result.pixels = glyph_pixels;
    
            return result;
        }

        return .();
    }
}
