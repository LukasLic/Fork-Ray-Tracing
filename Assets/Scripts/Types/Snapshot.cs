using UnityEngine;

public class Snapshot
{
    public RenderTexture Image { get; set; }
    public Vector3 Position { get; set; }
    public readonly int Id;

    public Snapshot(int id)
    {
        Id = id;
    }

    public void ResetRenderTexture()
    {
        ShaderHelper.Release(Image);

        RenderTexture r = null;
        ShaderHelper.CreateRenderTexture(
                ref r,
                Screen.width,
                Screen.height,
                FilterMode.Bilinear,
                ShaderHelper.RGBA_SFloat,
                $"Snapshot_{Id}");

        Image = r;
    }
}