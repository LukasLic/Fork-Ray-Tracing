using UnityEngine;

public class RT_PointLight : MonoBehaviour
{
    [Range(0.01f, 20f)] public float intensity = 1f;
    [Range(0.01f, 10f)] public float range = 1f;

    // Draw the point light in the editor
    private void OnDrawGizmos()
    {
        Gizmos.color = Color.yellow;

        // Draw a circle (x, z) to represent the light range
        int segments = 36;
        float angleStep = 360f / segments;
        Vector3 previousPoint = transform.position + new Vector3(range, 0, 0);
        for (int i = 1; i <= segments; i++)
        {
            float angle = i * angleStep * Mathf.Deg2Rad;
            Vector3 newPoint = transform.position + new Vector3(Mathf.Cos(angle) * range, 0, Mathf.Sin(angle) * range);
            Gizmos.DrawLine(previousPoint, newPoint);
            previousPoint = newPoint;
        }
    }
}
