using UnityEngine;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class SnapshotCloudRenderer : MonoBehaviour
{
    [Header("Material")]
    [SerializeField] private Shader cloudShader;

    [Header("Cloud settings")]
    [SerializeField] private int step = 32;
    [SerializeField] private float sizePixels = 2.0f;
    [SerializeField] private float maxDistance = 5000f;

    private Material _mat;
    private CommandBuffer _cb;
    private Camera _cam;

    private RenderTexture _snapshotTex;
    private Vector3 _snapCamPos;
    private Matrix4x4 _snapCamLocalToWorld;
    private Vector3 _snapViewParams;

    void OnEnable()
    {
        _cam = GetComponent<Camera>();

        if (cloudShader == null)
            cloudShader = Shader.Find("Hidden/SnapshotCloudBillboards");

        _mat = new Material(cloudShader);

        _cb = new CommandBuffer { name = "Snapshot Cloud" };
        _cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, _cb);
    }

    void OnDisable()
    {
        if (_cam != null && _cb != null)
            _cam.RemoveCommandBuffer(CameraEvent.AfterForwardOpaque, _cb);

        if (_cb != null) _cb.Release();
        _cb = null;

        if (_mat != null) DestroyImmediate(_mat);
        _mat = null;
    }

    public void SetSnapshot(RenderTexture snapshotTex, Vector3 snapCamPos, Matrix4x4 snapCamLocalToWorld, Vector3 snapViewParams, float maxDist)
    {
        _snapshotTex = snapshotTex;
        _snapCamPos = snapCamPos;
        _snapCamLocalToWorld = snapCamLocalToWorld;
        _snapViewParams = snapViewParams;
        maxDistance = maxDist;
    }

    void LateUpdate()
    {
        if (_cb == null) return;
        _cb.Clear();

        if (_snapshotTex == null || _mat == null) return;

        var s = Mathf.Max(1, step);
        var gridW = Mathf.Max(1, _snapshotTex.width / s);
        var gridH = Mathf.Max(1, _snapshotTex.height / s);
        var pointCount = gridW * gridH;
        var vertexCount = pointCount * 6;

        _mat.SetTexture("_SnapshotTex", _snapshotTex);
        _mat.SetVector("_SnapCamPos", _snapCamPos);
        _mat.SetMatrix("_SnapCamLocalToWorld", _snapCamLocalToWorld);
        _mat.SetVector("_SnapViewParams", _snapViewParams);

        _mat.SetFloat("_MaxDistance", maxDistance);
        _mat.SetFloat("_SizePixels", sizePixels);
        _mat.SetFloat("_Step", s);

        _cb.SetRenderTarget(BuiltinRenderTextureType.CameraTarget, BuiltinRenderTextureType.Depth);
        _cb.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, vertexCount, 1);
    }

    //void OnPostRender()
    //{
    //    if (_cb == null) return;
    //    _cb.Clear();

    //    if (_snapshotTex == null || _mat == null) return;

    //    var s = Mathf.Max(1, step);
    //    var gridW = Mathf.Max(1, _snapshotTex.width / s);
    //    var gridH = Mathf.Max(1, _snapshotTex.height / s);
    //    var pointCount = gridW * gridH;
    //    var vertexCount = pointCount * 6;

    //    _mat.SetTexture("_SnapshotTex", _snapshotTex);
    //    _mat.SetVector("_SnapCamPos", _snapCamPos);
    //    _mat.SetMatrix("_SnapCamLocalToWorld", _snapCamLocalToWorld);
    //    _mat.SetVector("_SnapViewParams", _snapViewParams);

    //    _mat.SetFloat("_MaxDistance", maxDistance);
    //    _mat.SetFloat("_SizePixels", sizePixels);
    //    _mat.SetFloat("_Step", s);

    //    _mat.SetPass(0);

    //    _cb.SetRenderTarget(BuiltinRenderTextureType.CameraTarget, BuiltinRenderTextureType.Depth);
    //    _cb.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, vertexCount, 1);
    //    //if (Input.GetKey(KeyCode.Mouse1) == false) return;

    //    //if (mat == null || points == null) return;

    //    //mat.SetBuffer("_Points", points);
    //    //mat.SetFloat("_SizePixels", sizePixels);

    //    //mat.SetPass(0);

    //    //// 4 points * 2 triangles * 3 verts = 24 verts
    //    //Graphics.DrawProceduralNow(MeshTopology.Triangles, 4 * 6, 1);
    //}
}
