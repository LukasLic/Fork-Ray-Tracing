using UnityEngine;

[RequireComponent(typeof(Camera))]
public class PyramidPointsRenderer : MonoBehaviour
{
    [SerializeField] Shader shader;
    [SerializeField] float sizePixels = 10f;

    Material mat;
    ComputeBuffer points;

    void OnEnable()
    {
        if (shader == null)
            shader = Shader.Find("Hidden/DebugPointBillboards");

        mat = new Material(shader);

        var pts = new Vector3[4];
        pts[0] = new Vector3(-1f, 0f, -1f);
        pts[1] = new Vector3(1f, 0f, -1f);
        pts[2] = new Vector3(0f, 0f, 1f);
        pts[3] = new Vector3(0f, 1.2f, 0f);

        points = new ComputeBuffer(4, sizeof(float) * 3);
        points.SetData(pts);
    }

    void OnDisable()
    {
        if (points != null) points.Release();
        points = null;

        if (mat != null) DestroyImmediate(mat);
        mat = null;
    }

    void OnPostRender()
    {
        if (Input.GetKey(KeyCode.Mouse1) == false) return; 

        if (mat == null || points == null) return;

        mat.SetBuffer("_Points", points);
        mat.SetFloat("_SizePixels", sizePixels);

        mat.SetPass(0);

        // 4 points * 2 triangles * 3 verts = 24 verts
        Graphics.DrawProceduralNow(MeshTopology.Triangles, 4 * 6, 1);
    }
}
