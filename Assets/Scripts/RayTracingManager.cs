using System;
using System.Collections.Generic;
using UnityEngine;
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
        Normal = 4
    }

    private bool initialized = false;

    // Game Controlled params
    [HideInInspector] public bool isRecording = false;

    [Header("Control")]
    [SerializeField] bool alwaysRecord = false;

    [Header("Final Renderers")]
    [SerializeField] private SnapshotCloudRenderer cloudRenderer;
    private Matrix4x4 snapshotCamLocalToWorld = Matrix4x4.identity;
    private Vector3 snapshotViewParams = Vector3.one;

    [Header("Main Settings")]
    [SerializeField] bool rayTracingEnabled = true;
    [SerializeField] float timeBetweenSnapshots = 1f;
    public bool accumulate = true;
    public bool useSky;
    [SerializeField] float sunFocus = 500;
    [SerializeField] float sunIntensity = 10;
    [SerializeField] Color sunColor = Color.white;

    [SerializeField, Range(0, 32)] int maxBounceCount = 4;
    [SerializeField, Range(0, 64)] int numRaysPerPixel = 2;
    [SerializeField, Range(0, 1)] float sampleChance = 1;
    [SerializeField, Min(0)] float defocusStrength = 0;
    [SerializeField, Min(0)] float divergeStrength = 0.3f;
    [SerializeField, Min(0)] float focusDistance = 1;

    [Header("Mask Settings")]
    [SerializeField] bool useRaytracingMask;
    [SerializeField] Texture raytracingMask;
    [SerializeField] GameObject MaskGui;

    [Header("Denoiser Settings")]
    [SerializeField] bool useDenoiser;
    [SerializeField, Range(0.01f, 1f)] float denoiserSigmaColor = 0.15f;
    [SerializeField] float denoiserSigmaDist = 0.10f;
    [SerializeField] float denoiserSigmaDistScale = 0.08f;

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

    [Header("Info")]
    [SerializeField] int numAccumulatedFrames;

    // Materials and render textures
    Material rayTracingMaterial;
    Material accumulateMaterial;
    Material composeMaterial;
    RenderTexture resultTexture;
    RenderTexture composedTexture;
    RenderTexture frameCountTexture;

    // Buffers
    ComputeBuffer triangleBuffer;
    ComputeBuffer nodeBuffer;
    ComputeBuffer modelBuffer;

    private Vector3 snapshotCamPos = Vector3.zero;
    private Matrix4x4 snapshotViewProj = Matrix4x4.identity;

    // Snaphots are "photos" of the real space at specific positions.
    private readonly Dictionary<int, Snapshot> Snapshots = new();

    MeshInfo[] meshInfo;
    Model[] models;
    bool hasBVH;
    LocalKeyword debugVisShaderKeyword;

    private int _width = 0;
    private int _height = 0;

    private Camera _camera;

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

        var cam = Camera.current;
        if(cam == null) {
            cam = GetComponent<Camera>();
        }
        cam.depthTextureMode |= DepthTextureMode.Depth;
    }

    private void Start()
    {
        ShaderHelper.Release(resultTexture);
        ShaderHelper.Release(composedTexture);

        ShaderHelper.Release(frameCountTexture);
        Destroy(frameCountTexture);

        foreach (var snapshot in Snapshots.Values)
        {
            // Null-safe
            ShaderHelper.Release(snapshot.Image);
        }

        _camera = GetComponent<Camera>();
    }

    //private void Update()
    //{
    //    if (Input.GetKeyDown(KeyCode.Space))
    //    {
    //        numAccumulatedFrames = 1;
    //        Debug.Log("Reset render");
    //    }

    //    if (Input.GetKeyDown(KeyCode.S))
    //    {
    //        string path = System.IO.Path.Combine(Application.persistentDataPath, "screencap_ray.png");
    //        ScreenCapture.CaptureScreenshot(path);
    //        Debug.Log("Screenshot: " + path);
    //    }
    //}

    private void LateUpdate()
    {
        numAccumulatedFrames = Mathf.Max(1, numAccumulatedFrames);

        MaskGui.SetActive(useRaytracingMask && raytracingMask != null);

        //if (!Application.isPlaying || Camera.current.name == "SceneCamera")
        //{
        //    Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
        //    return;
        //}

        //bool isSceneCam = Camera.current.name == "SceneCamera";
        bool isSceneCam = false;

        // Debug.Log("Rendering... isscenecam = " + isSceneCam + "  " + Camera.current.name);
        if (isSceneCam)
        {
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
            //Camera.current.cullingMask = rayTracingEnabled ? 0 : 2147483647;

            if (rayTracingEnabled && !useSceneView)
            {
                InitFrame();

                // FIXME: TRUE here (to automatically record) causes visual noise!
                isRecording = Input.GetKey(KeyCode.Mouse0) || Input.GetKeyDown(KeyCode.X) || (alwaysRecord && initialized);
                if (Input.GetKeyDown(KeyCode.Mouse0))
                {
                    timeSinceLastSnapshot = 0;
                    RenderTexture empty = RenderTexture.GetTemporary(_width, _height, 0, ShaderHelper.RGBA_SFloat);
                    Graphics.Blit(empty, resultTexture);

                    RenderTexture.ReleaseTemporary(empty);

                    // Store snapshot data
                    var cam = _camera;
                    var proj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, true);
                    var view = cam.worldToCameraMatrix;
                    snapshotCamPos = cam.transform.position;
                    snapshotViewProj = proj * view;
                }

                if (visMode == VisMode.Default)
                {
                    // Update timer
                    timeSinceLastSnapshot += isRecording ? Time.deltaTime : 0f;

                    // TODO: Initialize new snapshot with weight to 0.

                    if (isRecording && (timeSinceLastSnapshot >= timeBetweenSnapshots || timeBetweenSnapshots == 0f))
                    {
                        //Debug.Log("Time since last snapshot: " + Math.Round((decimal)timeSinceLastSnapshot, 4));
                        // Reset timer
                        timeSinceLastSnapshot = 0f;

                        // Create copy of prev frame
                        RenderTexture prevFrameCopy = RenderTexture.GetTemporary(_width, _height, 0, ShaderHelper.RGBA_SFloat);
                        Graphics.Blit(resultTexture, prevFrameCopy);

                        
                        float planeHeight = focusDistance * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2;
                        float planeWidth = planeHeight * _camera.aspect;
                        rayTracingMaterial.SetVector("ViewParams", new Vector3(planeWidth, planeHeight, focusDistance));
                        rayTracingMaterial.SetMatrix("CamLocalToWorldMatrix", _camera.transform.localToWorldMatrix);

                        rayTracingMaterial.SetInt("Frame", numAccumulatedFrames);
                        rayTracingMaterial.SetInt("UseRaytracingMask", useRaytracingMask && raytracingMask != null ? 1 : 0);
                        rayTracingMaterial.SetTexture("_RTMask", raytracingMask);

                        // Run the ray tracing shader and draw the result to a temp texture
                        RenderTexture currentFrame = RenderTexture.GetTemporary(_width, _height, 0, ShaderHelper.RGBA_SFloat);
                        Graphics.Blit(null, currentFrame, rayTracingMaterial);

                        // Accumulate
                        Graphics.SetRandomWriteTarget(1, frameCountTexture);
                        accumulateMaterial.SetInt("_Frame", numAccumulatedFrames);
                        accumulateMaterial.SetInt("_Accumulate", accumulate ? 1 : 0);
                        accumulateMaterial.SetTexture("_PrevFrame", prevFrameCopy);
                        Graphics.Blit(currentFrame, resultTexture, accumulateMaterial);
                        Graphics.ClearRandomWriteTargets();

                        // #############################################################################################################
                        // #############################################################################################################

                        // Store snapshot data
                        var cam = _camera;
                        var proj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, true);
                        var view = cam.worldToCameraMatrix;
                        snapshotCamPos = cam.transform.position;
                        snapshotViewProj = proj * view;
                        var snapshotCamLocalToWorld = cam.transform.localToWorldMatrix;

                        composeMaterial.SetVector("_CurViewParams", new Vector3(planeWidth, planeHeight, focusDistance));
                        composeMaterial.SetMatrix("_CurCamLocalToWorld", cam.transform.localToWorldMatrix);

                        composeMaterial.SetVector("_SnapCamPos", snapshotCamPos);
                        composeMaterial.SetMatrix("_SnapViewProj", snapshotViewProj);
                        composeMaterial.SetMatrix("_SnapCamLocalToWorld", snapshotCamLocalToWorld);

                        composeMaterial.SetFloat("_MaxDistance", 5000f);
                        composeMaterial.SetFloat("_DepthEps", 0.5f);
                        composeMaterial.SetFloat("_DepthEpsRelative", 0.02f);

                        composeMaterial.SetInt("_Smooth", useDenoiser ? 1 : 0);
                        composeMaterial.SetFloat("_sigmaColor", denoiserSigmaColor);
                        composeMaterial.SetFloat("_sigmaDist", denoiserSigmaDist);
                        composeMaterial.SetFloat("_sigmaDistScale", denoiserSigmaDistScale);

                        composeMaterial.SetTexture("_Snapshot01", resultTexture);
                        //composeMaterial.SetTexture("_MainTex", src); // TEMPORARILY COMMENTED OUT

                        // current view goes in as _MainTex
                        Graphics.Blit(null, composedTexture, composeMaterial); // TEMPORARILY COMMENTED OUT | Graphics.Blit(src, composedTexture, composeMaterial);
                        //Graphics.Blit(composedTexture, target); // TEMPORARILY COMMENTED OUT

                        // #############################################################################################################
                        // #############################################################################################################
                        /*
                        //// Create copy for composing
                        //RenderTexture resultCopy = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
                        //Graphics.Blit(resultTexture, resultCopy);

                        // Compose the final image and draw it to screen
                        composeMaterial.SetTexture("_Snapshot01", resultTexture);
                        Graphics.Blit(null, composedTexture, composeMaterial);

                        // Draw result to screen
                        //Graphics.Blit(resultTexture, target);
                        Graphics.Blit(composedTexture, target);
                        */
                        // #############################################################################################################
                        // #############################################################################################################

                        //Graphics.Blit(resultTexture, target); // TEMPORARILY COMMENTED OUT

                        // Release temps
                        RenderTexture.ReleaseTemporary(prevFrameCopy);
                        RenderTexture.ReleaseTemporary(currentFrame);
                        //RenderTexture.ReleaseTemporary(resultCopy);

                        numAccumulatedFrames += Application.isPlaying ? 1 : 0;

                        // #############################################################################################################
                        snapshotCamPos = _camera.transform.position;
                        snapshotCamLocalToWorld = _camera.transform.localToWorldMatrix;
                        snapshotViewParams = new Vector3(planeWidth, planeHeight, focusDistance);

                        if (cloudRenderer != null)
                        {
                            cloudRenderer.SetSnapshot(resultTexture, snapshotCamPos, snapshotCamLocalToWorld, snapshotViewParams, 5000f);
                        }
                        // #############################################################################################################
                    }
                    else
                    {
                        //var cam = Camera.current;
                        //var planeHeight = focusDistance * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2f;
                        //var planeWidth = planeHeight * cam.aspect;

                        //composeMaterial.SetVector("_CurViewParams", new Vector3(planeWidth, planeHeight, focusDistance));
                        //composeMaterial.SetMatrix("_CurCamLocalToWorld", cam.transform.localToWorldMatrix);

                        //composeMaterial.SetVector("_SnapCamPos", snapshotCamPos);
                        //composeMaterial.SetMatrix("_SnapViewProj", snapshotViewProj);

                        //composeMaterial.SetFloat("_MaxDistance", 5000f);
                        //composeMaterial.SetFloat("_DepthEps", 0.5f);
                        //composeMaterial.SetFloat("_DepthEpsRelative", 0.02f);

                        //composeMaterial.SetTexture("_Snapshot01", resultTexture);
                        //composeMaterial.SetTexture("_MainTex", src);

                        //// current view goes in as _MainTex
                        //Graphics.Blit(src, composedTexture, composeMaterial);
                        //Graphics.Blit(composedTexture, target);

                        // #############################################################################################################
                        // #############################################################################################################
                        // #############################################################################################################
                        // #############################################################################################################
                        //rayTracingMaterial.SetInt("rayPosOnly", 1);
                        //rayTracingMaterial.SetVector("_SnapCamPos", snapshotCamPos);
                        //rayTracingMaterial.SetMatrix("_SnapViewProj", snapshotViewProj);
                        //rayTracingMaterial.SetTexture("_Snapshot01", resultTexture);

                        //RenderTexture currentFrame = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
                        //Graphics.Blit(null, currentFrame, rayTracingMaterial);

                        //Graphics.Blit(currentFrame, target);

                        //RenderTexture.ReleaseTemporary(currentFrame);
                        // #############################################################################################################
                        // #############################################################################################################
                        // #############################################################################################################
                        // #############################################################################################################

                        /*
                        // Draw result to screen
                        //Graphics.Blit(resultTexture, target);
                        //Graphics.Blit(composedTexture, target);

                        // Compose the final image and draw it to screen
                        composeMaterial.SetTexture("_Snapshot01", resultTexture);
                        Graphics.Blit(null, composedTexture, composeMaterial);

                        // Draw result to screen
                        //Graphics.Blit(resultTexture, target);
                        Graphics.Blit(composedTexture, target);
                        */
                    }
                }
                else
                {
                    numAccumulatedFrames = 0;
                    //Graphics.Blit(null, target, rayTracingMaterial); // TEMPORARILY COMMENTED OUT
                }
            }
            else
            {
                //Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
            }
        }
    }

    // Called after any camera (e.g. game or scene camera) has finished rendering into the src texture
    void OnRenderImage(RenderTexture src, RenderTexture target)
    {
        numAccumulatedFrames = Mathf.Max(1, numAccumulatedFrames);

        _width = src.width;
        _height = src.height;

        //if (!Application.isPlaying || Camera.current.name == "SceneCamera")
        //{
        //    Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
        //    return;
        //}

        bool isSceneCam = Camera.current.name == "SceneCamera";
        // Debug.Log("Rendering... isscenecam = " + isSceneCam + "  " + Camera.current.name);
        if (isSceneCam)
        {
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
            //Camera.current.cullingMask = rayTracingEnabled ? 0 : 2147483647;

            if (rayTracingEnabled && !useSceneView)
            {
                InitFrame();

                // FIXME: TRUE here (to automatically record) causes visual noise!
                isRecording = Input.GetKey(KeyCode.Mouse0) || Input.GetKeyDown(KeyCode.X) || (alwaysRecord && initialized);

                if (visMode == VisMode.Default)
                {
                    if(isRecording)
                    {
                        Graphics.Blit(composedTexture, target);
                    }
                    else
                    {
                        Graphics.Blit(src, target);
                    }
                }
                else
                {
                    numAccumulatedFrames = 0;
                    Graphics.Blit(null, target, rayTracingMaterial);
                }
            }
            else
            {
                //Graphics.Blit(src, target); // Draw the unaltered camera render to the screen
            }
        }

        initialized = true;
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

        if (ShaderHelper.CreateRenderTexture(ref resultTexture, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "Result"))
        {
            Debug.Log("Created Result texture");
        }

        if (ShaderHelper.CreateRenderTexture(ref composedTexture, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "Composed"))
        {
            Debug.Log("Created Composed texture");
        }

        if (ShaderHelper.CreateFrameCountTexture(ref frameCountTexture, Screen.width, Screen.height, "FrameCount"))
        {
            Debug.Log("Created FrameCount texture");
        }
        
        models = FindObjectsOfType<Model>();

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
        UpdateCameraParams(_camera);
        SetShaderParams();
    }

    void SetShaderParams()
    {
        rayTracingMaterial.SetKeyword(debugVisShaderKeyword, visMode != VisMode.Default);
        rayTracingMaterial.SetInt("visMode", (int)visMode);
        float debugVisScale = visMode switch
        {
            VisMode.TriangleTestCount => triTestVisScale,
            VisMode.BoxTestCount => boxTestVisScale,
            VisMode.Distance => distanceTestVisScale,
            _ => triTestVisScale
        };
        rayTracingMaterial.SetFloat("debugVisScale", debugVisScale);
        rayTracingMaterial.SetInt("Frame", numAccumulatedFrames);
        rayTracingMaterial.SetInt("UseSky", useSky ? 1 : 0);

        rayTracingMaterial.SetInt("MaxBounceCount", maxBounceCount);
        rayTracingMaterial.SetInt("NumRaysPerPixel", numRaysPerPixel);
        rayTracingMaterial.SetFloat("SampleChance", sampleChance);
        rayTracingMaterial.SetFloat("DefocusStrength", defocusStrength);
        rayTracingMaterial.SetFloat("DivergeStrength", divergeStrength);

        rayTracingMaterial.SetFloat("SunFocus", sunFocus);
        rayTracingMaterial.SetFloat("SunIntensity", sunIntensity);
        rayTracingMaterial.SetColor("SunColour", sunColor);

        rayTracingMaterial.SetInt("rayPosOnly", 0);
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
            meshInfo[i].Material = models[i].material;
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
                meshLookup.Add(model.Mesh, (allData.nodes.Count, allData.triangles.Count));

                BVH bvh = new(model.Mesh.vertices, model.Mesh.triangles, model.Mesh.normals);
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

            ShaderHelper.Release(frameCountTexture);
            Destroy(frameCountTexture);

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
        public Matrix4x4 WorldToLocalMatrix;
        public Matrix4x4 LocalToWorldMatrix;
        public RayTracingMaterial Material;
    }
}
