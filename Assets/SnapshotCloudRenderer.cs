using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class SnapshotCloudRenderer : MonoBehaviour
{
    //[SerializeField] Shader splatShader;
    //[SerializeField] Material splatMaterial;
    //[SerializeField] RenderTexture snapshot;

    //public Vector3 snapshotCamPos;
    //public Matrix4x4 snapshotCamLocalToWorld;
    //public Vector3 snapshotViewParams;

    //private const float maxDistance = 5000f;
    //[SerializeField] float splatSizeWorld = 0.02f;

    //CommandBuffer _cb;
    //Mesh _quad;
    //Camera _cam;

    //void OnEnable()
    //{
    //    _cam = GetComponent<Camera>();
    //    _quad = CreateQuadMesh();

    //    if (splatMaterial == null || splatMaterial.shader != splatShader)
    //    {
    //        ShaderHelper.InitMaterial(splatShader, ref splatMaterial);
    //    }
        
    //    _cb = new CommandBuffer { name = "SnapshotCloud" };
    //    _cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, _cb);
    //}

    //void OnDisable()
    //{
    //    if (_cam != null && _cb != null) _cam.RemoveCommandBuffer(CameraEvent.AfterForwardOpaque, _cb);
    //    if (_cb != null) _cb.Release();
    //    _cb = null;

    //    if (_quad != null) Destroy(_quad);
    //    _quad = null;
    //}

    //void LateUpdate()
    //{
    //    if (_cb == null) return;
    //    _cb.Clear();

    //    if (snapshot == null || splatMaterial == null) return;

    //    var instanceCount = snapshot.width * snapshot.height;

    //    splatMaterial.SetTexture("_SnapshotTex", snapshot);
    //    splatMaterial.SetVector("_SnapshotCamPos", snapshotCamPos);
    //    splatMaterial.SetMatrix("_SnapshotCamLocalToWorld", snapshotCamLocalToWorld);
    //    splatMaterial.SetVector("_SnapshotViewParams", snapshotViewParams);
    //    splatMaterial.SetFloat("_MaxDistance", maxDistance);
    //    splatMaterial.SetFloat("_SplatSizeWorld", splatSizeWorld);

    //    _cb.SetRenderTarget(BuiltinRenderTextureType.CameraTarget, BuiltinRenderTextureType.Depth);
    //    _cb.DrawMeshInstancedProcedural(_quad, 0, splatMaterial, 0, instanceCount);
    //}

    //static Mesh CreateQuadMesh()
    //{
    //    var m = new Mesh();
    //    m.vertices = new[]
    //    {
    //        new Vector3(-0.5f, -0.5f, 0),
    //        new Vector3( 0.5f, -0.5f, 0),
    //        new Vector3( 0.5f,  0.5f, 0),
    //        new Vector3(-0.5f,  0.5f, 0),
    //    };
    //    m.uv = new[]
    //    {
    //        new Vector2(0,0),
    //        new Vector2(1,0),
    //        new Vector2(1,1),
    //        new Vector2(0,1),
    //    };
    //    m.triangles = new[] { 0, 1, 2, 0, 2, 3 };
    //    m.RecalculateBounds();
    //    return m;
    //}

    //private void OnDestroy()
    //{
    //    Destroy(splatMaterial);
    //}
}
