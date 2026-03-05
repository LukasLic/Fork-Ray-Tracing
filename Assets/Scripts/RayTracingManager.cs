using System;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.PlayerLoop;
using UnityEngine.Rendering;
using static UnityEngine.GraphicsBuffer;

public class RayTracingManager : MonoBehaviour
{
    public enum VisMode
    {
        Default = 0,
        TriangleTestCount = 1,
        BoxTestCount = 2,
        Distance = 3,
        Normal = 4,
        Shadowing = 5
    }

    private enum ShadowingStep
    {
        RaycastOriginal = 0,
        RaycastShadows = 1,
        CreateShadowMap = 2,
        ComposeResult = 3,
    }

    private bool IsRecording => autoRecordMaxFrame > 0
        ? (autoRecord && numAccumulatedFrames < autoRecordMaxFrame) || (Input.GetKey(KeyCode.LeftControl) && Input.GetKey(KeyCode.Mouse0))
        : autoRecord || (Input.GetKey(KeyCode.LeftControl) && Input.GetKey(KeyCode.Mouse0));

    [Header("Main Settings")]
    [SerializeField] bool rayTracingEnabled = true;
    [SerializeField] int autoRecordMaxFrame = 1000;
    [SerializeField] bool autoRecord = true;
    [SerializeField] float timeBetweenSnapshots = 1f;
    [SerializeField] int sectorCountX = 24;
    [SerializeField] int sectorCountY = 8;
    [SerializeField] bool accumulate = true;
    [Range(1, 5)]
    [SerializeField] int denoise = 0;
    [SerializeField] bool useSky;
    [SerializeField] float sunFocus = 500;
    [SerializeField] float sunIntensity = 10;
    [SerializeField] Color sunColor = Color.white;

    [SerializeField, Range(0, 32)] int maxBounceCount = 4;
    [SerializeField, Range(0, 64)] int numRaysPerPixel = 2;
    [SerializeField, Min(0)] float defocusStrength = 0;
    [SerializeField, Min(0)] float divergeStrength = 0.3f;
    [SerializeField, Min(0)] float focusDistance = 1;

    [Header("Shadowing")]
    [SerializeField] List<Model> shadowModels = new();
    [Range(0.0f, 20.0f)][SerializeField] float appliedShadowScale = 1f;
    private ShadowingStep shadowingStep = ShadowingStep.RaycastOriginal;

    // Add near your other serialized fields
    [Header("Overlay Duplicate")]
    [SerializeField] private Vector3 overlayDuplicateWorldOffset = Vector3.zero;
    [SerializeField] private GameObject overlayDuplicatePrefab;
    [SerializeField] private Transform overlayDuplicateParent;
    [SerializeField] private Material overlayDuplicateMaterial;
    [SerializeField] private int overlayDuplicateLayer = 7;
    [SerializeField] private Camera overlayDuplicateCamera;
    private GameObject overlayDuplicateInstance;


    [Header("Debug Settings")]
    [SerializeField] VisMode visMode;
    [SerializeField] float triTestVisScale;
    [SerializeField] float boxTestVisScale;
    [SerializeField] float distanceTestVisScale;
    [SerializeField] bool useSceneView;

    [Header("References")]
    [SerializeField] Shader rayTracingShader;
    [SerializeField] Shader accumulateShader;
    [SerializeField] Shader composeShader;
    [SerializeField] Shader shadowmapShader;

    [Header("Info")]
    [SerializeField] int numAccumulatedFrames;

    // Materials and render textures
    Material rayTracingMaterial;
    Material accumulateMaterial;
    Material composeMaterial;
    Material shadowmapMaterial;
    RenderTexture resultTexture;
    RenderTexture composedTexture;
    RenderTexture overlayCameraTexture;
    RenderTexture frameCountTexture;

    RenderTexture resultTexture_copy;
    RenderTexture shadowmap;

    // Normal maps fields
    Texture2DArray normalMapArray;
    Dictionary<Texture2D, int> normalMapIndexByTexture = new();
    int normalMapHash;

    // Buffers
    ComputeBuffer triangleBuffer;
    ComputeBuffer nodeBuffer;
    ComputeBuffer modelBuffer;

    // Snaphots are "photos" of the real space at specific positions.
    private readonly Dictionary<int, Snapshot> Snapshots = new();

    MeshInfo[] meshInfo;
    Model[] models;
    bool hasBVH;
    LocalKeyword debugVisShaderKeyword;

    /// <summary>
    /// [seconds]
    /// </summary>
    private float timeSinceLastSnapshot = 9999f;

    private void ResetSnapshot(int i)
    {
        Snapshots[i].ResetRenderTexture();
    }

    private void OnEnable()
    {
        numAccumulatedFrames = 0;
        hasBVH = false;
        if (visMode == VisMode.Shadowing) shadowingStep = ShadowingStep.RaycastOriginal;
    }

    private void Awake()
    {
        CreateOverlayDuplicate();

        ShaderHelper.CreateRenderTexture(ref overlayCameraTexture, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "OverlayCamera", DepthMode.Depth24);
        overlayDuplicateCamera.enabled = false; // We will manually trigger rendering and blit the result in OnRenderImage
    }

    private void Update()
    {
        //if (Input.GetKeyDown(KeyCode.Space))
        //{
        //    numAccumulatedFrames = 1;
        //    Debug.Log("Reset render");
        //}

        if (Input.GetKey(KeyCode.LeftControl) && Input.GetKeyDown(KeyCode.F))
        {
            var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
            var filename = $"screencap_ray_{timestamp}.png";
            string path = System.IO.Path.Combine(Application.persistentDataPath, filename);
            ScreenCapture.CaptureScreenshot(path);
            Debug.Log("Screenshot: " + path);
        }

        overlayDuplicateCamera.targetTexture = overlayCameraTexture;
        overlayDuplicateCamera.Render();
    }

    // Called after any camera (e.g. game or scene camera) has finished rendering into the src texture
    void OnRenderImage(RenderTexture src, RenderTexture target)
    {
        if (!Application.isPlaying)
        {
            Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
            return;
        }

        bool isSceneCam = Camera.current.name == "SceneCamera";
        // Debug.Log("Rendering... isscenecam = " + isSceneCam + "  " + Camera.current.name);
        if (isSceneCam)
        {
            Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
            //if (rayTracingEnabled && useSceneView && Application.isPlaying)
            //{
            //    InitFrame();
            //    Graphics.Blit(null, target, rayTracingMaterial);
            //}
            //else
            //{
            //    Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
            //}
        }
        else
        {
            Camera.current.cullingMask = rayTracingEnabled ? 0 : 2147483647;

            if (rayTracingEnabled && !useSceneView)
            {
                InitFrame();

                if (visMode == VisMode.Default)
                {
                    BlitDefault(src, target);
                }
                else if (visMode == VisMode.Shadowing)
                {
                    BlitShadowSteps(src, target);
                }
                else
                {
                    numAccumulatedFrames = 0;
                    Graphics.Blit(null, target, rayTracingMaterial);
                }
            }
            else
            {
                Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
            }
        }
    }

    private void BlitShadowSteps(RenderTexture src, RenderTexture target)
    {
        rayTracingMaterial.SetInt("ShadowMask", 0);

        // ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
        if (shadowingStep == ShadowingStep.RaycastOriginal)
        {
            // Set shadow casters to invisible so they don't interfere with the original raycast
            if (numAccumulatedFrames <= 1)
            {
                //shadowModels.ForEach(x => x.material = RayTracingMaterial.DuplicateFrom(x.material, RayTracingMaterial.MaterialFlag.Invisible));
                shadowModels.ForEach(x => x.material.flag = RayTracingMaterial.MaterialFlag.Invisible);
            }

            if (IsRecording) BlitDefault(src, target);
            else
            {
                Graphics.Blit(resultTexture, resultTexture_copy);
                shadowingStep = ShadowingStep.RaycastShadows;
                numAccumulatedFrames = 0;
                shadowModels.ForEach(x => x.material.flag = RayTracingMaterial.MaterialFlag.None);
            }
        }
        // ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
        if (shadowingStep == ShadowingStep.RaycastShadows)
        {
            if (IsRecording)
            {
                rayTracingMaterial.SetInt("ShadowMask", 1);
                BlitDefault(src, target);
                rayTracingMaterial.SetInt("ShadowMask", 0);
            }
            else
            {
                shadowingStep = ShadowingStep.CreateShadowMap;
                numAccumulatedFrames = 0;
            }
        }
        // ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
        if (shadowingStep == ShadowingStep.CreateShadowMap)
        {

            shadowmapMaterial.SetTexture("_TexRT", resultTexture_copy);
            shadowmapMaterial.SetTexture("_TexShadow", resultTexture);
            shadowmapMaterial.SetFloat("_AppliedShadowScale", appliedShadowScale);

            Graphics.Blit(null, shadowmap, shadowmapMaterial);

            shadowingStep = ShadowingStep.ComposeResult;
            //numAccumulatedFrames = 0;
        }
        // ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
        if (shadowingStep == ShadowingStep.ComposeResult)
        {
            // SKIP (for now)
            //BlitDefault(src, target);

            //overlayDuplicateCamera.targetTexture = overlayCameraTexture;
            //overlayDuplicateCamera.Render();

            composeMaterial.SetTexture("_Snapshot01", shadowmap);
            composeMaterial.SetInt("_Denoise", denoise);
            composeMaterial.SetVector("_Snapshot01_TexelSize",
                new Vector4(
                    1f / resultTexture.width,
                    1f / resultTexture.height,
                    resultTexture.width,
                    resultTexture.height));
            composeMaterial.SetInt("_OverlayEnabled", 1);
            composeMaterial.SetTexture("_OverlayTex", overlayCameraTexture);
            Graphics.Blit(null, target, composeMaterial);

            //Graphics.Blit(shadowmap, target);
        }
        // ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    }

    private void BlitDefault(RenderTexture src, RenderTexture target)
    {
        

        // Update timer
        timeSinceLastSnapshot += IsRecording ? Time.deltaTime : 0f;

        // TODO: Initialize new snapshot with weight to 0.

        if (IsRecording && timeSinceLastSnapshot >= timeBetweenSnapshots)
        {
            //Debug.Log("Time since last snapshot: " + Math.Round((decimal)timeSinceLastSnapshot, 4));
            // Reset timer
            timeSinceLastSnapshot = 0f;

            // Create copy of prev frame
            RenderTexture prevFrameCopy = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
            Graphics.Blit(resultTexture, prevFrameCopy);

            // Run the ray tracing shader and draw the result to a temp texture
            rayTracingMaterial.SetInt("Frame", numAccumulatedFrames);
            RenderTexture currentFrame = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
            Graphics.Blit(null, currentFrame, rayTracingMaterial);

            // Accumulate
            //Graphics.SetRandomWriteTarget(1, frameCountTexture);
            accumulateMaterial.SetInt("_Frame", numAccumulatedFrames);
            accumulateMaterial.SetInt("_Accumulate", accumulate ? 1 : 0);
            accumulateMaterial.SetTexture("_PrevFrame", prevFrameCopy);
            Graphics.Blit(currentFrame, resultTexture, accumulateMaterial);
            //Graphics.ClearRandomWriteTargets();

            // Create copy for composing
            RenderTexture resultCopy = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
            Graphics.Blit(resultTexture, resultCopy);

            composeMaterial.SetTexture("_Snapshot01", resultTexture);
            composeMaterial.SetInt("_Denoise", denoise);
            composeMaterial.SetVector("_Snapshot01_TexelSize",
                new Vector4(
                    1f / resultTexture.width,
                    1f / resultTexture.height,
                    resultTexture.width,
                    resultTexture.height));
            composeMaterial.SetInt("_OverlayEnabled", 0);
            Graphics.Blit(null, target, composeMaterial);

            //// Compose the final image and draw it to screen
            //composeMaterial.SetTexture("_Snapshot01", resultTexture);
            //Graphics.Blit(null, composedTexture, composeMaterial);

            //// Draw result to screen
            ////Graphics.Blit(resultTexture, target);
            //Graphics.Blit(composedTexture, target);

            // Release temps
            RenderTexture.ReleaseTemporary(prevFrameCopy);
            RenderTexture.ReleaseTemporary(currentFrame);
            RenderTexture.ReleaseTemporary(resultCopy);
            numAccumulatedFrames += Application.isPlaying ? 1 : 0;
        }
        else
        {
            // Draw result to screen
            //Graphics.Blit(resultTexture, target);
            //Graphics.Blit(composedTexture, target);

            // Compose the final image and draw it to screen
            composeMaterial.SetTexture("_Snapshot01", resultTexture);
            composeMaterial.SetVector("_Snapshot01_TexelSize",
                new Vector4(
                    1f / resultTexture.width,
                    1f / resultTexture.height,
                    resultTexture.width,
                    resultTexture.height));
            Graphics.Blit(null, composedTexture, composeMaterial);

            // Draw result to screen
            //Graphics.Blit(resultTexture, target);
            Graphics.Blit(composedTexture, target);
        }
    }

    void InitFrame()
    {
        // Create materials used in blits
        if (rayTracingMaterial == null || rayTracingMaterial.shader != rayTracingShader)
        {
            ShaderHelper.InitMaterial(rayTracingShader, ref rayTracingMaterial);
            debugVisShaderKeyword = new LocalKeyword(rayTracingShader, "DEBUG_VIS");
        }
        ShaderHelper.InitMaterial(accumulateShader, ref accumulateMaterial);
        ShaderHelper.InitMaterial(composeShader, ref composeMaterial);
        ShaderHelper.CreateRenderTexture(ref resultTexture, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "Result");
        ShaderHelper.CreateRenderTexture(ref composedTexture, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "Composed");
        ShaderHelper.CreateFrameCountTexture(ref frameCountTexture, Screen.width, Screen.height, "FrameCount");

        ShaderHelper.InitMaterial(shadowmapShader, ref shadowmapMaterial);
        ShaderHelper.CreateRenderTexture(ref resultTexture_copy, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "ResultCopy");
        ShaderHelper.CreateRenderTexture(ref shadowmap, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "ResultShadow");


        models = FindObjectsOfType<Model>();

        EnsureNormalMapArray(models);

        if (!hasBVH)
        {
            var data = CreateAllMeshData(models);
            hasBVH = true;

            meshInfo = data.meshInfo.ToArray();
            ShaderHelper.CreateStructuredBuffer(ref modelBuffer, meshInfo);

            // Triangles buffer
            ShaderHelper.CreateStructuredBuffer(ref triangleBuffer, data.triangles);
            rayTracingMaterial.SetBuffer("Triangles", triangleBuffer);
            rayTracingMaterial.SetInt("triangleCount", triangleBuffer.count);

            // Node buffer
            ShaderHelper.CreateStructuredBuffer(ref nodeBuffer, data.nodes);
            rayTracingMaterial.SetBuffer("Nodes", nodeBuffer);
        }
        UpdateModels();
        // Update data
        UpdateCameraParams(Camera.current);
        SetShaderParams();
    }

    void SetShaderParams()
    {
        rayTracingMaterial.SetKeyword(debugVisShaderKeyword, visMode != VisMode.Default && visMode != VisMode.Shadowing);
        rayTracingMaterial.SetInt("visMode", (int)visMode);
        float debugVisScale = visMode switch
        {
            VisMode.TriangleTestCount => triTestVisScale,
            VisMode.BoxTestCount => boxTestVisScale,
            VisMode.Distance => distanceTestVisScale,
            _ => triTestVisScale
        };
        rayTracingMaterial.SetFloat("debugVisScale", debugVisScale);
        rayTracingMaterial.SetInt("ShadowMask", 0);
        rayTracingMaterial.SetInt("Frame", numAccumulatedFrames);
        rayTracingMaterial.SetInt("UseSky", useSky ? 1 : 0);

        rayTracingMaterial.SetInt("MaxBounceCount", maxBounceCount);
        rayTracingMaterial.SetInt("NumRaysPerPixel", numRaysPerPixel);
        rayTracingMaterial.SetFloat("DefocusStrength", defocusStrength);
        rayTracingMaterial.SetFloat("DivergeStrength", divergeStrength);

        rayTracingMaterial.SetFloat("SunFocus", sunFocus);
        rayTracingMaterial.SetFloat("SunIntensity", sunIntensity);
        rayTracingMaterial.SetColor("SunColour", sunColor);
    }

    void UpdateCameraParams(Camera cam)
    {
        float planeHeight = focusDistance * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2;
        float planeWidth = planeHeight * cam.aspect;
        // Send data to shader
        rayTracingMaterial.SetVector("ViewParams", new Vector3(planeWidth, planeHeight, focusDistance));
        rayTracingMaterial.SetMatrix("CamLocalToWorldMatrix", cam.transform.localToWorldMatrix);
    }

    void UpdateModels()
    {
        for (int i = 0; i < models.Length; i++)
        {
            meshInfo[i].WorldToLocalMatrix = models[i].transform.worldToLocalMatrix;
            meshInfo[i].LocalToWorldMatrix = models[i].transform.localToWorldMatrix;
            //meshInfo[i].Material = models[i].material;

            var mat = models[i].material;
            ApplyNormalMapParams(models[i], ref mat);
            meshInfo[i].Material = mat;
        }
        modelBuffer.SetData(meshInfo);
        rayTracingMaterial.SetBuffer("ModelInfo", modelBuffer);
        rayTracingMaterial.SetInt("modelCount", models.Length);
    }

    MeshDataLists CreateAllMeshData(Model[] models)
    {
        MeshDataLists allData = new();
        Dictionary<Mesh, (int nodeOffset, int triOffset)> meshLookup = new();

        foreach (Model model in models)
        {
            // Construct BVH if this is the first time seeing the current mesh (otherwise reuse)
            if (!meshLookup.ContainsKey(model.Mesh))
            {
                var mesh = model.Mesh;
                meshLookup.Add(model.Mesh, (allData.nodes.Count, allData.triangles.Count));

                var uvs = mesh.uv;
                var tangents = mesh.tangents;

                if (uvs == null || uvs.Length != mesh.vertexCount)
                    uvs = new Vector2[mesh.vertexCount];

                if (tangents == null || tangents.Length != mesh.vertexCount)
                {
                    mesh.RecalculateTangents();
                    tangents = mesh.tangents;

                    if (tangents == null || tangents.Length != mesh.vertexCount)
                        tangents = new Vector4[mesh.vertexCount];
                }

                BVH bvh = new BVH(mesh.vertices, mesh.triangles, mesh.normals, uvs, tangents);
                if (model.logBVHStats) Debug.Log($"BVH Stats: {model.gameObject.name}\n{bvh.stats}");

                allData.triangles.AddRange(bvh.GetTriangles());
                allData.nodes.AddRange(bvh.GetNodes());
            }

            // Create the mesh info
            allData.meshInfo.Add(new MeshInfo()
            {
                NodeOffset = meshLookup[model.Mesh].nodeOffset,
                TriangleOffset = meshLookup[model.Mesh].triOffset,
                WorldToLocalMatrix = model.transform.worldToLocalMatrix,
                LocalToWorldMatrix = model.transform.localToWorldMatrix,
                Material = model.material
            });
        }

        return allData;
    }

    class MeshDataLists
    {

        public List<Triangle> triangles = new();
        public List<BVH.Node> nodes = new();
        public List<MeshInfo> meshInfo = new();
    }

    void OnDestroy()
    {
        if (Application.isPlaying)
        {
            ShaderHelper.Release(triangleBuffer, nodeBuffer, modelBuffer);
            ShaderHelper.Release(resultTexture);
            ShaderHelper.Release(composedTexture);
            ShaderHelper.Release(overlayCameraTexture);
            ShaderHelper.Release(frameCountTexture);

            ShaderHelper.Release(resultTexture_copy);
            ShaderHelper.Release(shadowmap);

            Destroy(rayTracingMaterial);

            foreach (var snapshot in Snapshots.Values)
            {
                // Null-safe
                ShaderHelper.Release(snapshot.Image);
            }
        }
    }

    void OnValidate()
    {
    }

    struct MeshInfo
    {
        public int NodeOffset;
        public int TriangleOffset;
        public Matrix4x4 WorldToLocalMatrix; // TODO: For static images, this may be able to be precomputed into the BVH
        public Matrix4x4 LocalToWorldMatrix; // TODO: For static images, this may be able to be precomputed into the BVH
        public RayTracingMaterial Material;
    }

    int ComputeNormalMapHash(Model[] srcModels)
    {
        unchecked
        {
            var hash = 17;

            for (var i = 0; i < srcModels.Length; i++)
            {
                var renderer = srcModels[i].GetComponent<Renderer>();
                var unityMat = renderer != null ? renderer.sharedMaterial : null;

                var tex = (Texture2D)null;
                //if (unityMat != null && unityMat.HasProperty("_BumpMap"))
                //    tex = unityMat.GetTexture("_BumpMap") as Texture2D;
                tex = srcModels[i].normalMap;

                hash = hash * 31 + (tex != null ? tex.GetInstanceID() : 0);
            }

            return hash;
        }
    }

    void EnsureNormalMapArray(Model[] srcModels)
    {
        var hash = ComputeNormalMapHash(srcModels);
        if (normalMapArray != null && hash == normalMapHash)
            return;

        normalMapHash = hash;

        var unique = new List<Texture2D>();
        var seen = new HashSet<Texture2D>();

        for (var i = 0; i < srcModels.Length; i++)
        {
            //var renderer = srcModels[i].GetComponent<Renderer>();
            //var unityMat = renderer != null ? renderer.sharedMaterial : null;

            //if (unityMat == null || !unityMat.HasProperty("_BumpMap"))
            //    continue;

            //var tex = unityMat.GetTexture("_BumpMap") as Texture2D;
            //if (tex == null)
            //    continue;
            var model = srcModels[i];
            if (model.normalMap == null)
            {
                continue;
            }

            var tex = model.normalMap;

            if (seen.Add(tex))
                unique.Add(tex);
        }

        normalMapArray = NormalMapArrayBuilder.Build(unique, out normalMapIndexByTexture);

        if (normalMapArray != null)
            rayTracingMaterial.SetTexture("_NormalMaps", normalMapArray);
    }

    void ApplyNormalMapParams(Model model, ref RayTracingMaterial rtMat)
    {
        var renderer = model.GetComponent<Renderer>();
        var unityMat = renderer != null ? renderer.sharedMaterial : null;

        var normalTex = (Texture2D)null;
        var uvScale = Vector2.one;
        var uvOffset = Vector2.zero;

        //if (unityMat != null && unityMat.HasProperty("_BumpMap"))
        //{
        //    normalTex = unityMat.GetTexture("_BumpMap") as Texture2D;
        //    uvScale = unityMat.GetTextureScale("_BumpMap");
        //    uvOffset = unityMat.GetTextureOffset("_BumpMap");

        //    if (unityMat.HasProperty("_BumpScale"))
        //        bumpScale = unityMat.GetFloat("_BumpScale");
        //}
        normalTex = model.normalMap;

        rtMat.normalMapIndex =
            (normalTex != null && normalMapIndexByTexture.TryGetValue(normalTex, out var idx))
                ? idx
                : -1;

        //rtMat.normalScale = bumpScale; // Assume 1 for now
        rtMat.normalScale = Math.Max(1, rtMat.normalScale); // Avoid zero scale
        rtMat.uvST = new Vector4(uvScale.x, uvScale.y, uvOffset.x, uvOffset.y);
    }

    /// <summary>
    /// Instantiates <see cref="overlayDuplicatePrefab"/> (optionally under <see cref="overlayDuplicateParent"/>),
    /// then performs cleanup and setup:
    /// <list type="number">
    /// <item><description>Deletes every GameObject in the spawned hierarchy that has a <see cref="Model"/> component (active or inactive).</description></item>
    /// <item><description>Recursively sets <see cref="overlayDuplicateLayer"/> on all remaining objects.</description></item>
    /// <item><description>For each <see cref="MeshRenderer"/>, replaces all materials with <see cref="overlayDuplicateMaterial"/>.</description></item>
    /// </list>
    /// </summary>
    private void CreateOverlayDuplicate(bool force = true)
    {
        //if (overlayDuplicatePrefab != null && overlayDuplicateParent != null && overlayDuplicateMaterial != null)
        //{
        //    overlayDuplicateInstance = Instantiate(overlayDuplicatePrefab, overlayDuplicateParent);
        //    var renderers = overlayDuplicateInstance.GetComponentsInChildren<MeshRenderer>();
        //    foreach (var renderer in renderers)
        //    {
        //        renderer.sharedMaterial = overlayDuplicateMaterial;
        //        renderer.gameObject.layer = overlayDuplicateLayer;
        //    }
        //}
        if (overlayDuplicatePrefab == null)
            return;

        if (overlayDuplicateInstance != null)
            if (force) Destroy(overlayDuplicateInstance);
            else return;

        overlayDuplicateInstance = overlayDuplicateParent != null
                        ? Instantiate(overlayDuplicatePrefab, overlayDuplicateWorldOffset, Quaternion.identity, overlayDuplicateParent)
                        : Instantiate(overlayDuplicatePrefab, overlayDuplicateWorldOffset, Quaternion.identity);

        overlayDuplicateInstance.name = $"{overlayDuplicatePrefab.name}_OverlayDuplicate";

        RemoveModelGameObjectsRecursive(overlayDuplicateInstance.transform);
        if (overlayDuplicateInstance == null)
            return;

        ApplyOverlaySettingsRecursive(overlayDuplicateInstance.transform);
    }

    /// <summary>
    /// Finds all <see cref="Model"/> components under <paramref name="root"/> (including inactive objects),
    /// and destroys their owning GameObjects. If the root itself carries a <see cref="Model"/>,
    /// only the component is removed to avoid destroying the spawned instance root.
    /// </summary>
    /// <param name="root">Root transform of the spawned overlay duplicate hierarchy.</param>
    private void RemoveModelGameObjectsRecursive(Transform root)
    {
        var models = root.GetComponentsInChildren<Model>(true);

        for (var i = 0; i < models.Length; i++)
        {
            var model = models[i];
            if (model == null)
                continue;

            var go = model.gameObject;
            if (go == null)
                continue;

            if (model.material.flag != RayTracingMaterial.MaterialFlag.Invisible &&
                model.material.flag != RayTracingMaterial.MaterialFlag.InvisibleLight)
                continue;

            if (overlayDuplicateInstance != null && go == overlayDuplicateInstance)
            {
                Destroy(model);
                continue;
            }

            Destroy(go);
        }
    }

    /// <summary>
    /// Recursively applies overlay settings to <paramref name="t"/> and all descendants:
    /// sets the GameObject layer to <see cref="overlayDuplicateLayer"/> and, if a <see cref="MeshRenderer"/> is present,
    /// replaces all renderer materials with <see cref="overlayDuplicateMaterial"/>.
    /// </summary>
    /// <param name="t">Current transform node being processed.</param>
    private void ApplyOverlaySettingsRecursive(Transform t)
    {
        if (t == null)
            return;

        t.gameObject.layer = overlayDuplicateLayer;

        if (t.gameObject.TryGetComponent<ParticleSystem>(out var ps))
            ps.Play();

        var meshRenderer = t.GetComponent<MeshRenderer>();
        if (meshRenderer != null && overlayDuplicateMaterial != null)
        {
            var shared = meshRenderer.sharedMaterials;
            if (shared != null && shared.Length > 0)
            {
                var mats = new Material[shared.Length];
                for (var m = 0; m < mats.Length; m++)
                    mats[m] = overlayDuplicateMaterial;

                meshRenderer.sharedMaterials = mats;
            }
            else
            {
                meshRenderer.sharedMaterial = overlayDuplicateMaterial;
            }
        }

        for (var i = 0; i < t.childCount; i++)
            ApplyOverlaySettingsRecursive(t.GetChild(i));
    }
}
