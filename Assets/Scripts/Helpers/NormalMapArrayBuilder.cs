using System;
using System.Collections.Generic;
using UnityEngine;

public static class NormalMapArrayBuilder
{
    /// <summary>
    /// Builds a Texture2DArray from a set of Texture2D normal maps and returns a lookup that maps each texture to its slice index.
    /// </summary>
    /// <param name="textures">
    /// List of source textures (each becomes one slice). Null entries are allowed and will be skipped.
    /// </param>
    /// <param name="indexByTexture">
    /// Output dictionary mapping a source Texture2D instance to the slice index used in the returned Texture2DArray.
    /// </param>
    /// <returns>
    /// A Texture2DArray containing the copied textures, or null if no valid texture was provided.
    /// </returns>
    /// <exception cref="InvalidOperationException">
    /// Thrown if any non-null texture does not match the reference texture in width, height, format, or mip count.
    /// </exception>
    public static Texture2DArray Build(
        IReadOnlyList<Texture2D> textures,
        out Dictionary<Texture2D, int> indexByTexture)
    {
        indexByTexture = new Dictionary<Texture2D, int>(textures.Count);

        Texture2D reference = null;
        for (var i = 0; i < textures.Count; i++)
        {
            var tex = textures[i];
            if (tex != null)
            {
                reference = tex;
                break;
            }
        }

        if (reference == null)
            return null;

        var width = reference.width;
        var height = reference.height;
        var format = reference.format;
        var mipCount = reference.mipmapCount;

        var array = new Texture2DArray(width, height, textures.Count, format, mipCount > 1, linear: true);
        array.wrapMode = reference.wrapMode;
        array.filterMode = reference.filterMode;

        for (var slice = 0; slice < textures.Count; slice++)
        {
            var tex = textures[slice];
            if (tex == null)
                continue;

            if (tex.width != width || tex.height != height || tex.format != format || tex.mipmapCount != mipCount)
                throw new InvalidOperationException("All normal maps in the array must share size, format, and mip count.");

            indexByTexture[tex] = slice;

            for (var mip = 0; mip < mipCount; mip++)
                Graphics.CopyTexture(tex, 0, mip, array, slice, mip);
        }

        array.Apply(false, true);
        return array;
    }
}
