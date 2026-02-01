using Unity.Mathematics;
using UnityEngine;

public readonly struct Triangle
{
    public readonly Vector3 PosA;
    public readonly Vector3 PosB;
    public readonly Vector3 PosC;

    public readonly Vector3 NormalA;
    public readonly Vector3 NormalB;
    public readonly Vector3 NormalC;

    public readonly float2 UvA;
    public readonly float2 UvB;
    public readonly float2 UvC;

    public readonly float4 TanA;
    public readonly float4 TanB;
    public readonly float4 TanC;

    public Triangle(
        Vector3 posA, Vector3 posB, Vector3 posC,
        Vector3 normalA, Vector3 normalB, Vector3 normalC,
        Vector2 uvA, Vector2 uvB, Vector2 uvC,
        Vector4 tanA, Vector4 tanB, Vector4 tanC
    )
    {
        this.PosA = posA;
        this.PosB = posB;
        this.PosC = posC;
        this.NormalA = normalA;
        this.NormalB = normalB;
        this.NormalC = normalC;
        this.UvA = uvA;
        this.UvB = uvB;
        this.UvC = uvC;
        this.TanA = tanA;
        this.TanB = tanB;
        this.TanC = tanC;
    }
}