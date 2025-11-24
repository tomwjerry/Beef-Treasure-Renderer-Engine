namespace Treasure.Optional;

class FreetypeLoader
{
    public FT_Library ft_library;
    public List<FT_Face> ft_faces;

    public static void LoadFont(out Font font)
    {
        if (font.err)
        {
            return;
        }

        font.err = FT_Init_FreeType(this.ft_library);
        for enum_values_as_enum(FONT_Family)
        {
            if err break;
            if it.(s64) > G.ast.fonts.count
            {
            log_error("Font %(%) is missing in .pie file. Loaded fonts count: %", it, it.(s64), G.ast.fonts.count);
            break;
            }

            font_data := G.ast.fonts[it];
            err = FT_New_Memory_Face(ft_library, font_data.data, xx font_data.count, 0, *ft_faces[it]);
        }

        font.MaybeResizeAtlasTexture();
    }
}
