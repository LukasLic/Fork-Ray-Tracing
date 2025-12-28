using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

[RequireComponent(typeof(Camera))]
public class RayTracing2D : MonoBehaviour
{
    [Header("References")]
    [SerializeField] Shader rayTracingShader;
    [SerializeField] Shader worldPosShader;

    Camera _camera;
    [SerializeField] Camera worldPosCamera;

    // Materials and render textures
    Material rayTracingMaterial;
    ComputeBuffer lineBlockersBuffer;
    ComputeBuffer pointLightsBuffer;

    private const int MAX_POINT_LIGHTS = 127; // Must be same length as the shader!
    private const int MAX_BLOCKER_SEGMENTS = 1023; // Must be same length as the shader!

    private void OnEnable()
    {
        _camera = GetComponent<Camera>();
        _camera.depthTextureMode |= DepthTextureMode.Depth;
        _camera.allowHDR = true;

        worldPosCamera.depthTextureMode |= DepthTextureMode.Depth;
        worldPosCamera.allowHDR = true;

        // Create materials used in blits
        if (rayTracingMaterial == null || rayTracingMaterial.shader != rayTracingShader)
        {
            ShaderHelper.InitMaterial(rayTracingShader, ref rayTracingMaterial);
        }
    }

    private void LateUpdate()
    {
        var boxObstacles = FindObjectsOfType<RT_BoxObstacle>();
        var lineBlockersData = new List<float4>();

        foreach (var box in boxObstacles)
        {
            var lines = box.GetLines();
            for (int i = 0; i < lines.Count; i++)
            {
                if (i >= MAX_BLOCKER_SEGMENTS)
                {
                    Debug.LogError("Exceeded max blocker segments limit: " + MAX_BLOCKER_SEGMENTS);
                    break;
                }

                var A = new Vector3(
                    lines[i].x,
                    1,
                    lines[i].y);

                var B = new Vector3(
                    lines[(i + 1) % lines.Count].x,
                    1,
                    lines[(i + 1) % lines.Count].y);

                Debug.DrawLine(A, B, Color.red);
                lineBlockersData.Add(new float4()
                {
                    x = lines[i].x,
                    y = lines[i].y,
                    z = lines[(i + 1) % lines.Count].x,
                    w = lines[(i + 1) % lines.Count].y,
                });
            }
        }

        ShaderHelper.CreateStructuredBuffer(ref lineBlockersBuffer, lineBlockersData.ToArray());

        var lights = FindObjectsOfType<RT_PointLight>();
        var lightData = new List<float4>();

        for (int i = 0; i < lights.Length; i++)
        {
            if(i >= MAX_POINT_LIGHTS)
            {
                Debug.LogError("Exceeded max point lights limit: " + MAX_POINT_LIGHTS);
                break;
            }

            var light = lights[i];

            lightData.Add(new float4()
            {
                x = light.transform.position.x,
                y = light.transform.position.z,
                z = light.range,
                w = light.intensity,
            });
        }

        ShaderHelper.CreateStructuredBuffer(ref pointLightsBuffer, lightData.ToArray());
        //pointLightsBuffer.SetData(lightDataList.ToArray());
    }

    private void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        // Capture world position into a temporary HDR texture immediately.
        var worldPosRT = RenderTexture.GetTemporary(
            src.width,
            src.height,
            depthBuffer: 24, // [bits]
            RenderTextureFormat.ARGBFloat,
            RenderTextureReadWrite.Linear,
            antiAliasing: 1); // = None

        worldPosRT.filterMode = FilterMode.Point;
        worldPosRT.wrapMode = TextureWrapMode.Clamp;

        worldPosCamera.targetTexture = worldPosRT;
        worldPosCamera.RenderWithShader(worldPosShader, "RenderType");

        rayTracingMaterial.SetInt("BlockerSegmentCount", lineBlockersBuffer != null ? lineBlockersBuffer.count : 0);
        rayTracingMaterial.SetBuffer("BlockerSegments", lineBlockersBuffer);
        rayTracingMaterial.SetInt("PointLightCount", pointLightsBuffer != null ? pointLightsBuffer.count : 0);
        rayTracingMaterial.SetBuffer("PointLights", pointLightsBuffer);
        rayTracingMaterial.SetTexture("_CameraWorldPositions", worldPosRT);
        rayTracingMaterial.SetTexture("_CameraColor", src);

        Graphics.Blit(null, dest, rayTracingMaterial);

        worldPosCamera.targetTexture = null;
        RenderTexture.ReleaseTemporary(worldPosRT);
    }

    private void OnDestroy()
    {
        if (Application.isPlaying)
        {
            Destroy(rayTracingMaterial);
            ShaderHelper.Release(lineBlockersBuffer);
            ShaderHelper.Release(pointLightsBuffer);
        }
    }
}
