using System.Collections.Generic;
using UnityEngine;

[RequireComponent(typeof(BoxCollider))]
public class RT_BoxObstacle : MonoBehaviour
{
    /// <summary>
    /// Gets the lines that represent the edges of the box.
    /// </summary>
    /// <returns>A list of Vector4 representing the lines of the box (x1, z1, x2, z2).</returns>
    public List<Vector4> GetLines()
    {
        var lines = new List<Vector4>();

        // Get the BoxCollider component
        var boxCollider = GetComponent<BoxCollider>();

        // Calculate the corners of the box
        Vector3 center = boxCollider.center;
        Vector3 size = boxCollider.size;

        Vector3[] corners = new Vector3[4];
        corners[0] = transform.TransformPoint(center + new Vector3(-size.x, 0, -size.z) * 0.5f);
        corners[1] = transform.TransformPoint(center + new Vector3(size.x, 0, -size.z) * 0.5f);
        corners[2] = transform.TransformPoint(center + new Vector3(size.x, 0, size.z) * 0.5f);
        corners[3] = transform.TransformPoint(center + new Vector3(-size.x, 0, size.z) * 0.5f);

        // Create lines between the corners
        for (int i = 0; i < corners.Length; i++)
        {
            lines.Add(new Vector4(corners[i].x, corners[i].z, corners[(i + 1) % corners.Length].x, corners[(i + 1) % corners.Length].z));
        }

        return lines;
    }
}
