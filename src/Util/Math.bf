namespace Treasure.Util;
using System;

// RANGE MATH
struct NumericRange<T> : Range<T>  where T : operator T + T where T : operator T - T where bool : operator T >= T
{
    public this()
    {
        this = default;
    }

    public this(T end)
    {
        this = default;
        mEnd = end;
    }

    public this(T start, T end)
    {
        mStart = start;
        mEnd = end;
    }

    public static NumericRange<T> MakeRangeMinDim(T min, T dim) where T : operator T + T
    {
        return NumericRange<T>(min, min + dim);
    }
    public static NumericRange<T> MakeRangeCenterHalfDim(T center, T half_dim) where T : operator T + T where T : operator T - T
    {
        return NumericRange<T>(center - half_dim, center + half_dim);
    }
    public static NumericRange<T> MakeRangeCenterDim(T center, T dim) where T : operator T + T where T : operator T - T where T : operator T / int
    {
        return NumericRange<T>(center - dim / 2, center + dim / 2);
    }

    public static bool operator==(NumericRange<T> a, NumericRange<T> b)
    {
      return a.mStart == b.mStart && a.mEnd == b.mEnd;
    }

    public static T RangeLength(NumericRange<T> r)
    {
        if (r.mEnd >= r.mStart)
        {
            return r.mEnd - r.mStart;
        }
        return default;
    }

    public static T DistanceBetweenRanges(NumericRange<T> a, NumericRange<T> b)
    {
        T d0 = b.mStart - a.mEnd;
        T d1 = a.mStart - b.mEnd;
        if (d0 >= d1)
        {
            return d0;
        }
        return d1;
    }

    public static bool OverlapsRange(NumericRange<T> r, T value)
    {
        return value >= r.mStart && r.mEnd >= value;
    }

    public NumericRange<T> Intersection(NumericRange<T> b)
    {
        NumericRange<T> result = NumericRange<T>(this.mStart, this.mEnd);
        if (b.mStart >= this.mStart)
        {
            result.mStart = b.mStart;
        }
        if (this.mEnd >= b.mEnd)
        {
            result.mEnd = b.mEnd;
        }
        return result;
    }

    public static void for_expansion(NumericRange<T> range, function void(T) body)
    {
        for (var r in range)
        {
            body(r);
        }
    }
}

// TYPES
interface Vector
{
}

struct Vector2f : Vector, IHashable
{
    public float X;
    public float Y;

    public this()
    {
        this = default;
    }

    public this(float x, float y)
    {
        X = x;
        Y = y;
    }

    public Vector2f Rotate(float turns)
    {
        let sincos = SinCos(turns);
        Vector2f res = Vector2f(
            this.X * sincos.1 + this.Y * -sincos.0,
            this.X * sincos.0 + this.Y * sincos.1
        );
        return res;
    }

    public bool HasLength()
    {
        return this.X != 0.0f || this.Y != 0.0f;
    }

    public Vector2f Clamp(Vector2f a, Vector2f b)
    {
        Vector2f res = Vector2f();
        res.X = Math.Clamp(this.X, a.X, b.X);
        res.Y = Math.Clamp(this.Y, a.X, b.X);
        return res;
    }

    public Vector2f Normalize()
    {
        Vector2f result = Vector2f();
        float factor = Distance(this, Vector2f());
        factor = 1f / factor;
        result.X = this.X * factor;
        result.Y = this.Y * factor;
        return result;
    }

    public int GetHashCode()
    {
        return this.X.GetHashCode() ^ this.Y.GetHashCode();
    }

    // VECTOR2 MATH
    public static Vector2f NormalFromSegment(Vector2f a, Vector2f b)
    {
        Vector2f direction = b - a;
        direction = direction.Normalize();
        Vector2f res = direction.Rotate(-0.25f);
        return res;
    }

    public static float DistanceSquared(Vector2f value1, Vector2f value2)
    {
        return (value1.X - value2.X) * (value1.X - value2.X) +
            (value1.Y - value2.Y) * (value1.Y - value2.Y);
    }

    public static float Distance(Vector2f vector1, Vector2f vector2)
    {
        float result = DistanceSquared(vector1, vector2);
        return (float)Math.Sqrt(result);
    }

    public static Vector2f operator+(Vector2f lhs, Vector2f rhs)
    {
        return .(lhs.X + rhs.X, lhs.Y + rhs.Y);
    }
    /* Unary '-' operator */
    public static Vector2f operator-(Vector2f lhs, Vector2f rhs)
    {
        return .(lhs.X - rhs.X, lhs.Y - rhs.Y);
    }
    // vec x vec
    public static Vector2f operator*(Vector2f a, Vector2f b)
    {
        return .(a.X * b.X, a.Y * b.Y);
    }
    public static Vector2f operator/(Vector2f a, Vector2f b)
    {
        return .(a.X / b.X, a.Y / b.Y);
    }
    public static Vector2f Min(Vector2f a, Vector2f b)
    {
        return .(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y));
    }
    public static Vector2f Max(Vector2f a, Vector2f b)
    {
        return .(Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));
    }

    // vec x scalar
    public static Vector2f operator/(Vector2f val, float scalar)
    {
        return .(val.X / scalar, val.Y / scalar);
    }
    public static Vector2f operator*(Vector2f val, float scalar)
    {
        return .(val.X * scalar, val.Y * scalar);
    }
    public static Vector2f Min(Vector2f val, float scalar)
    {
        return .(Math.Min(val.X, scalar), Math.Min(val.Y, scalar));
    }
    public static Vector2f Max(Vector2f val, float scalar)
    {
        return .(Math.Max(val.X, scalar), Math.Max(val.Y, scalar));
    }
}

struct Vector3f : Vector, IHashable 
{
    public float X;
    public float Y;
    public float Z;

    public this()
    {
        this = default;
    }

    public this(float x, float y, float z)
    {
        X = x;
        Y = y;
        Z = z;
    }

    public bool HasLength()
    {
        return this.X != 0.0f || this.Y != 0.0f || this.Z != 0;
    }

    public Vector3f Clamp(Vector3f a, Vector3f b)
    {
        Vector3f res = Vector3f(
            Math.Clamp(this.X, a.X, b.X),
            Math.Clamp(this.Y, a.Y, b.Y),
            Math.Clamp(this.Z, a.Z, b.Z));
        return res;
    }

    public Vector3f Rotate(Quat q)
    {
        return this.Transform(q.ToMatrix());
    }

    public Vector3f Transform(Mat4 matrix)
    {
        Vector3f result = Vector3f();
        result.X = (this.X * matrix._11) + (this.Y * matrix._12) +
            (this.Z * matrix._13) + matrix._14;
        result.Y = (this.X * matrix._21) + (this.Y * matrix._22) +
        (this.Z * matrix._23) + matrix._24;
        result.Z = (this.X * matrix._31) + (this.Y * matrix._32) +
            (this.Z * matrix._33) + matrix._34;
        return result;
    }

    public Vector3f Normalize()
    {
        Vector3f result = Vector3f();
        float factor = Distance(this, Vector3f());
        factor = 1f / factor;
        result.X = this.X * factor;
        result.Y = this.Y * factor;
        result.Z = this.Z * factor;
        return result;
    }

    
    public Vector2f XY()
    {
        return Vector2f(this.X, this.Y);
    }

    public int GetHashCode()
    {
        return this.X.GetHashCode() ^ this.Y.GetHashCode() ^ this.Z.GetHashCode();
    }

    public static float DistanceSquared(Vector3f value1, Vector3f value2)
    {
        return (value1.X - value2.X) * (value1.X - value2.X) +
            (value1.Y - value2.Y) * (value1.Y - value2.Y) +
            (value1.Z - value2.Z) * (value1.Z - value2.Z);
    }

    public static float Distance(Vector3f vector1, Vector3f vector2)
    {
        float result = DistanceSquared(vector1, vector2);
        return (float)Math.Sqrt(result);
    }

    public static float Dot(Vector3f vec1, Vector3f vec2)
    {
        return vec1.X * vec2.X + vec1.Y * vec2.Y + vec1.Z * vec2.Z;
    }

    public static Vector3f Lerp(Vector3f value1, Vector3f value2, float amount)
    {
        return Vector3f(
            Math.Lerp(value1.X, value2.X, amount),
            Math.Lerp(value1.Y, value2.Y, amount),
            Math.Lerp(value1.Z, value2.Z, amount)
        );
    }

    public static Vector3f Cross(Vector3f vector1, Vector3f vector2)
    {
        return Vector3f(vector1.Y * vector2.Z - vector2.Y * vector1.Z,
            -(vector1.X * vector2.Z - vector2.X * vector1.Z),
            vector1.X * vector2.Y - vector2.X * vector1.Y);
    }

    public static Vector3f operator+(Vector3f lhs, Vector3f rhs)
    {
        return .(lhs.X + rhs.X, lhs.Y + rhs.Y, lhs.Z + rhs.Z);
    }

    /* Unary '-' operator */
    public static Vector3f operator-(Vector3f lhs, Vector3f rhs)
    {
        return .(lhs.X - rhs.X, lhs.Y - rhs.Y, lhs.Z - rhs.Z);
    }

    public static Vector3f operator/(Vector3f val, float scalar)
    {
        return .(val.X / scalar, val.Y / scalar, val.Z / scalar);
    }

    public static Vector3f operator*(Vector3f val, float scalar)
    {
        return .(val.X * scalar, val.Y * scalar, val.Z * scalar);
    }
}

struct Vector4f : Vector
{
    public float X;
    public float Y;
    public float Z;
    public float W;

    public this()
    {
        this = default;
    }

    public this(float x, float y, float z, float w)
    {
        X = x;
        Y = y;
        Z = z;
        W = w;
    }

    public bool HasLength()
    {
        return this.X != 0.0f || this.Y != 0.0f || this.Z != 0 || this.W != 0.0;
    }

    public Vector3f XYZ()
    {
        return Vector3f(this.X, this.Y, this.Z);
    }

    public Vector4f Clamp(Vector4f a, Vector4f b)
    {
        Vector4f res = Vector4f(
            Math.Clamp(this.X, a.X, b.X),
            Math.Clamp(this.Y, a.Y, b.Y),
            Math.Clamp(this.Z, a.Z, b.Z),
            Math.Clamp(this.W, a.W, b.W));
        return res;
    }

    public static Vector4f Lerp(Vector4f value1, Vector4f value2, float amount)
    {
        return Vector4f(
            Math.Lerp(value1.X, value2.X, amount),
            Math.Lerp(value1.Y, value2.Y, amount),
            Math.Lerp(value1.Z, value2.Z, amount),
            Math.Lerp(value1.W, value2.W, amount)
        );
    }

    public static Vector4f operator+(Vector4f lhs, Vector4f rhs)
    {
        return .(lhs.X + rhs.X, lhs.Y + rhs.Y, lhs.Z + lhs.Z, lhs.W + lhs.W);
    }

    /* Unary '-' operator */
    public static Vector4f operator-(Vector4f lhs, Vector4f rhs)
    {
        return .(lhs.X - rhs.X, lhs.Y - rhs.Y, lhs.Z - rhs.Z, lhs.W - rhs.W);
    }

    public static Vector4f operator/(Vector4f val, float scalar)
    {
        return .(val.X / scalar, val.Y / scalar, val.Z / scalar, val.W / scalar);
    }
}

[Union]
struct Mat4 : IHashable // @todo change to row-major matrices in the future?
{
    // column-major Matrix 4x4
    // 0 4 8 c
    // 1 5 9 d
    // 2 6 a e
    // 3 7 b f

    // _yx
    public struct
    {
        public float _11;
        public float _21;
        public float _31;
        public float _41;
        public float _12;
        public float _22;
        public float _32;
        public float _42;
        public float _13;
        public float _23;
        public float _33;
        public float _43;
        public float _14;
        public float _24;
        public float _34;
        public float _44;
    };
    public float[16] flat;
    public float[4][4] elem; // elem[column][row]
    public Vector4f[4] cols; // cols[column]

    public this()
    {
        this = default;    
    }

    public this(
        float m00, float m01, float m02, float m03,
        float m10, float m11, float m12, float m13,
        float m20, float m21, float m22, float m23,
        float m30, float m31, float m32, float m33)
    {
        this._11 = m00;
        this._12 = m01;
        this._13 = m02;
        this._14 = m03;
        this._21 = m10;
        this._22 = m11;
        this._23 = m12;
        this._24 = m13;
        this._31 = m20;
        this._32 = m21;
        this._33 = m22;
        this._34 = m23;
        this._41 = m30;
        this._42 = m31;
        this._43 = m32;
        this._44 = m33;
    }

    public int GetHashCode()
    {
        return (int)this._11.GetHashCode() +
            (int)this._12.GetHashCode() +
            (int)this._13.GetHashCode() +
            (int)this._14.GetHashCode() +
            (int)this._21.GetHashCode() +
            (int)this._22.GetHashCode() +
            (int)this._23.GetHashCode() +
            (int)this._24.GetHashCode() +
            (int)this._31.GetHashCode() +
            (int)this._32.GetHashCode() +
            (int)this._33.GetHashCode() +
            (int)this._34.GetHashCode() +
            (int)this._41.GetHashCode() +
            (int)this._42.GetHashCode() +
            (int)this._43.GetHashCode() +
            (int)this._44.GetHashCode();
    }

    public static readonly Mat4 Identity = Mat4(
        1f, 0f, 0f, 0f,
        0f, 1f, 0f, 0f,
        0f, 0f, 1f, 0f,
        0f, 0f, 0f, 1f);

    // MATRIX MATH
    public static bool operator==(Mat4 a, Mat4 b)
    {
        for (int i = 0; i < 16; i++)
        {
            if (a.flat[i] != b.flat[i])
            {
                return false;
            }
        }
        return true;
    }

    public static Mat4 ScaleMatrix(Vector3f scale)
    {
        Mat4 res;
        res.elem[0][0] = scale.X;
        res.elem[1][1] = scale.Y;
        res.elem[2][2] = scale.Z;
        res.elem[3][3] = 1.0f;
        return res;
    }

    public static Mat4 ScaleMatrix(float scale)
    {
        Mat4 res;
        res.elem[0][0] = scale;
        res.elem[1][1] = scale;
        res.elem[2][2] = scale;
        res.elem[3][3] = 1.0f;
        return res;
    }

    public static Mat4 RotationMatrix(Quat q)
    {
        Quat norm = q.Normalize();
        float xx_ = norm.X * norm.X;
        float yy = norm.Y * norm.Y;
        float zz = norm.Z * norm.Z;
        float xy = norm.X * norm.Y;
        float xz = norm.X * norm.Z;
        float yz = norm.Y * norm.Z;
        float wx = norm.W * norm.X;
        float wy = norm.W * norm.Y;
        float wz = norm.W * norm.Z;

        Mat4 res = Mat4();
        res.elem[0][0] = 1.0f - 2.0f * (yy + zz);
        res.elem[0][1] = 2.0f * (xy + wz);
        res.elem[0][2] = 2.0f * (xz - wy);
        res.elem[0][3] = 0.0f;

        res.elem[1][0] = 2.0f * (xy - wz);
        res.elem[1][1] = 1.0f - 2.0f * (xx_ + zz);
        res.elem[1][2] = 2.0f * (yz + wx);
        res.elem[1][3] = 0.0f;

        res.elem[2][0] = 2.0f * (xz + wy);
        res.elem[2][1] = 2.0f * (yz - wx);
        res.elem[2][2] = 1.0f - 2.0f * (xx_ + yy);
        res.elem[2][3] = 0.0f;

        res.elem[3][0] = 0.0f;
        res.elem[3][1] = 0.0f;
        res.elem[3][2] = 0.0f;
        res.elem[3][3] = 1.0f;
        return res;
    }

    public static Mat4 DiagonalMatrix(float value = 1)
    {
        Mat4 res = Mat4();
        res.elem[0][0] = value;
        res.elem[1][1] = value;
        res.elem[2][2] = value;
        res.elem[3][3] = value;
        return res;
    }

    public static Mat4 TranslationMatrix(Vector3f move)
    {
        Mat4 res = DiagonalMatrix();
        res.elem[3][0] = move.X;
        res.elem[3][1] = move.Y;
        res.elem[3][2] = move.Z;
        return res;
    }

    public static Mat4 RotationMatrixAroundAxis(Vector3f axis_, float turns)
    {
        Vector3f axis = axis_.Normalize();
        let tsc = SinCos(turns);
        float c1 = 1.0f - tsc.1;

        Mat4 res = DiagonalMatrix();
        res.elem[0][0] = (axis.X * axis.X * c1) + tsc.1;
        res.elem[0][1] = (axis.X * axis.Y * c1) + (axis.Z * tsc.0);
        res.elem[0][2] = (axis.X * axis.Z * c1) - (axis.Y * tsc.0);

        res.elem[1][0] = (axis.Y * axis.X * c1) - (axis.Z * tsc.0);
        res.elem[1][1] = (axis.Y * axis.Y * c1) + tsc.1;
        res.elem[1][2] = (axis.Y * axis.Z * c1) + (axis.X * tsc.0);

        res.elem[2][0] = (axis.Z * axis.X * c1) + (axis.Y * tsc.0);
        res.elem[2][1] = (axis.Z * axis.Y * c1) - (axis.X * tsc.0);
        res.elem[2][2] = (axis.Z * axis.Z * c1) + tsc.1;
        return res;
    }

    public static Mat4 PerspectiveMatrix(float fov_y,
        float aspect_ratio, float near, float far)
    {
        // Modified to work with +x fordward, -y right, +z
        // up coordinate system (same as Source engine).
        float cotangent = 1.0f / Tan(fov_y * 0.5f);
        Mat4 res = Mat4();
        res.elem[0][2] = -far / (near - far); // X -> -Z
        res.elem[0][3] = 1.0f; // X -> W
        res.elem[1][0] = -cotangent / aspect_ratio; // -Y -> X
        res.elem[2][1] = cotangent; // Z -> Y
        res.elem[3][2] = (near * far) / (near - far); // W -> Z
        return res;
    }

    public static Mat4 OrthographicMatrix(float left, float right,
        float bottom, float top, float near, float far)
    {
        Mat4 res = Mat4();
        res.elem[0][2] = -1.0f / (near - far); // X -> -Z
        res.elem[1][0] = -2.0f / (right - left); // -Y -> X
        res.elem[2][1] = 2.0f / (top - bottom); // Z -> Y
        res.elem[3][3] = 1.0f; // W -> W

        res.elem[3][0] = (left + right) / (left - right); // W -> X
        res.elem[3][1] = (bottom + top) / (bottom - top); // W -> Y
        res.elem[3][2] = near / (near - far); // W -> Z
        return res;
    }

    public static Mat4 Multiply(Mat4 m, Mat4 n)
    {
        Mat4 result;

        result._11 = m._11 * n._11 + m._12 * n._21 + m._13 * n._31 + m._14 * n._41;
        result._21 = m._21 * n._11 + m._22 * n._21 + m._23 * n._31 + m._24 * n._41;
        result._31 = m._31 * n._11 + m._32 * n._21 + m._33 * n._31 + m._34 * n._41;
        result._41 = m._41 * n._11 + m._42 * n._21 + m._43 * n._31 + m._44 * n._41;

        result._12 = m._11 * n._12 + m._12 * n._22 + m._13 * n._32 + m._14 * n._42;
        result._22 = m._21 * n._12 + m._22 * n._22 + m._23 * n._32 + m._24 * n._42;
        result._32 = m._31 * n._12 + m._32 * n._22 + m._33 * n._32 + m._34 * n._42;
        result._42 = m._41 * n._12 + m._42 * n._22 + m._43 * n._32 + m._44 * n._42;

        result._13 = m._11 * n._13 + m._12 * n._23 + m._13 * n._33 + m._14 * n._43;
        result._23 = m._21 * n._13 + m._22 * n._23 + m._23 * n._33 + m._24 * n._43;
        result._33 = m._31 * n._13 + m._32 * n._23 + m._33 * n._33 + m._34 * n._43;
        result._43 = m._41 * n._13 + m._42 * n._23 + m._43 * n._33 + m._44 * n._43;

        result._14 = m._11 * n._14 + m._12 * n._24 + m._13 * n._34 + m._14 * n._44;
        result._24 = m._21 * n._14 + m._22 * n._24 + m._23 * n._34 + m._24 * n._44;
        result._34 = m._31 * n._14 + m._32 * n._24 + m._33 * n._34 + m._34 * n._44;
        result._44 = m._41 * n._14 + m._42 * n._24 + m._43 * n._34 + m._44 * n._44;

        return result;
    }
    public static Mat4 operator *(Mat4 a, Mat4 b)
    {
        return Multiply(a, b);
    }

    public static Vector4f Multiply(Mat4 m, Vector4f vec)
    {
        // @todo SIMD
        Vector4f res = Vector4f();
        res.X = vec.X * m.cols[0].X;
        res.Y = vec.X * m.cols[0].Y;
        res.Z = vec.X * m.cols[0].Z;
        res.W = vec.X * m.cols[0].W;

        res.X += vec.Y * m.cols[1].X;
        res.Y += vec.Y * m.cols[1].Y;
        res.Z += vec.Y * m.cols[1].Z;
        res.W += vec.Y * m.cols[1].W;

        res.X += vec.Z * m.cols[2].X;
        res.Y += vec.Z * m.cols[2].Y;
        res.Z += vec.Z * m.cols[2].Z;
        res.W += vec.Z * m.cols[2].W;

        res.X += vec.W * m.cols[3].X;
        res.Y += vec.W * m.cols[3].Y;
        res.Z += vec.W * m.cols[3].Z;
        res.W += vec.W * m.cols[3].W;
        return res;
    }
    public static Vector4f operator*(Mat4 m, Vector4f vec)
    {
        return Multiply(m, vec);
    }

    public static Mat4 transpose(Mat4 m)
    {
        Mat4 r = Mat4();
        for (int i = 0; i < 3; i++)
        {
            for (int j = 0; j < 3; j++)
            {
                r.elem[i][j] = m.elem[j][i];
            }
        }
        return r;
    }
}

struct Rect
{
    public Vector2f Min;
    public Vector2f Max;

    public this()
    {
        Min = Vector2f();
        Max = Vector2f();
    }

    public this(Vector2f min)
    {
        Min = min;
        Max = Vector2f();
    }

    public this(Vector2f min, Vector2f max)
    {
        Min = min;
        Max = max;
    }

    public this(float max_x, float max_y)
    {
        Min = Vector2f();
        Max = Vector2f(max_x, max_y);
    }
    public this(float x, float y, float max_x, float max_y)
    {
        Min = Vector2f(x, y);
        Max = Vector2f(max_x, max_y);
    }

    public Rect Intersection(Rect other)
    {
        Rect res = Rect(this.Min, this.Max);

        float x1 = Math.Max(this.Min.X, other.Min.X);
        float x2 = Math.Min(this.Max.X, other.Max.X);
        float y1 = Math.Max(this.Min.Y, other.Min.Y);
        float y2 = Math.Min(this.Max.Y, other.Max.Y);
        if (((x2 - x1) < 0) || ((y2 - y1) < 0))
        {
            res.Min.X = 0;
            res.Min.Y = 0;
            res.Max.X = 0;
            res.Max.Y = 0;
        }
        else
        {
            res.Min.X = x1;
            res.Min.Y = y2;
            res.Max.X = x2;
            res.Max.Y = y2;
        }

        return res;
    }

    public static Rect MakeRectMinDim(Vector2f min, Vector2f dim)
    {
        return .(min, min + dim);
    }
    public static Rect MakeRectCenterHalfDim(Vector2f center, Vector2f half_dim)
    {
        return .(center - half_dim, center + half_dim);
    }
    public static Rect MakeRectCenterDim(Vector2f center, Vector2f dim)
    {
        return .(center - dim / 2, center + dim / 2);
    }
    public static Rect MakeRectMinDim(float x, float y, float dim_x, float dim_y)
    {
        return .(.(x, y), .(x, y) + .(dim_x, dim_y));
    }
}

// AXIS MATH
enum Axis3
{
    X,
    Y,
    Z
}

struct Quat
{
    public float X;
    public float Y;
    public float Z;
    public float W;

    public this()
    {
        this = default;
    }

    public this(float x, float y, float z, float w)
    {
        X = x;
        Y = y;
        Z = z;
        W = w;
    }

    public Mat4 ToMatrix()
    {
        Mat4 matrix = Mat4.Identity;

        float fTx = X + X;
        float fTy = Y + Y;
        float fTz = Z + Z;
        float fTwx = fTx * W;
        float fTwy = fTy * W;
        float fTwz = fTz * W;
        float fTxx = fTx * X;
        float fTxy = fTy * X;
        float fTxz = fTz * X;
        float fTyy = fTy * Y;
        float fTyz = fTz * Y;
        float fTzz = fTz * Z;

        matrix._11 = 1.0f - (fTyy + fTzz);
        matrix._12 = fTxy - fTwz;
        matrix._13 = fTxz + fTwy;
        matrix._14 = 0.0f;

        matrix._21 = fTxy + fTwz;
        matrix._22 = 1.0f - (fTxx + fTzz);
        matrix._23 = fTyz - fTwx;
        matrix._24 = 0.0f;

        matrix._31 = fTxz - fTwy;
        matrix._32 = fTyz + fTwx;
        matrix._33 = 1.0f - (fTxx + fTyy);
        matrix._34 = 0.0f;

        matrix._41 = 0.0f;
        matrix._42 = 0.0f;
        matrix._43 = 0.0f;
        matrix._44 = 1.0f;

        return matrix;
    }

    public Quat Normalize()
    {
        Quat normalized = Quat(this.X, this.Y, this.Z, this.W);
        float num2 = (((this.X * this.X) + (this.Y * this.Y)) +
            (this.Z * this.Z)) + (this.W * this.W);
        float num = 1f / ((float)Math.Sqrt((double)num2));
        normalized.X *= num;
        normalized.Y *= num;
        normalized.Z *= num;
        normalized.W *= num;
        return normalized;
    }

    public static float Dot(Quat quaternion1, Quat quaternion2)
    {
        return ((((quaternion1.X * quaternion2.X) +
            (quaternion1.Y * quaternion2.Y)) +
            (quaternion1.Z * quaternion2.Z)) +
            (quaternion1.W * quaternion2.W));
    }

    // SCALAR MATH
    public static Quat DirectionXYToRotationZ(Vector3f not_normalized_dir3)
    {
        Vector2f dir = not_normalized_dir3.XY().Normalize();
        float turns = -Math.Atan2(dir.X, dir.Y) + 0.25f;
        turns = WrapFloat(-0.5f, 0.5f, turns);
        Quat rotation = RotationAroundAxis(AxisV3(.Z), turns);
        return rotation;
    }
    
    // QUATERNION MATH
    public static Quat RotationAroundAxis(Vector3f axis_, float turns) // Assumes Right Handed coordinate system
    {
        let sincos = SinCos(turns * 0.5f);
        Vector3f axis = axis_.Normalize();
        axis *= sincos.0;
        Quat res = Quat(
            axis.X,
            axis.Y,
            axis.Z,
            sincos.1
        );
        return res;
    }
    
    public static Quat RotationFromNormalizedPair(Vector3f a, Vector3f b)
    {
        Vector3f cr = Vector3f.Cross(a, b);
        Quat res = Quat(cr.X, cr.Y, cr.Z, 1.0f + Vector3f.Dot(a, b));
        return res;
    }
    
    public static Quat RotationFromPair(Vector3f a, Vector3f b)
    {
        return RotationFromNormalizedPair(a.Normalize(), b.Normalize());
    }
    
    public static Quat Mix(Quat a, Quat b, float weight_a, float weight_b)
    {
        Quat res = Quat(
            a.X * weight_a + b.X * weight_b,
            a.Y * weight_a + b.Y * weight_b,
            a.Z * weight_a + b.Z * weight_b,
            a.W * weight_a + b.W * weight_b
        );
        return res;
    }
    
    public static Quat Nlerp(Quat a, Quat b, float t)
    {
        return Mix(a, b, 1.0f - t, t);
    }
    
    public static Quat Slerp(Quat a, Quat b_, float t)
    {
        Quat b = b_;
    
        float cos_theta = Quat.Dot(a, b);
        if (cos_theta < 0.0f)
        {
            cos_theta = -cos_theta;
            b = -b;
        }
    
        if (cos_theta > 0.9995f)
        {
            // NOTE(lcf): Use Normalized Linear interpolation when vectors are roughly not L.I.
            return Nlerp(a, b, t);
        }
    
        float angle = Acos(cos_theta);
        float ta = Sin((1.0f - t) * angle);
        float tb = Sin(t * angle);
        
        Quat res = Mix(a, b, ta, tb);
        return res.Normalize();
    }
    
    public static Quat SlowMultiply(Quat a, Quat b)
    {
        // @todo SIMD
        Quat res = Quat();
        res.X = b.W * +a.X;
        res.Y = b.Z * -a.X;
        res.Z = b.Y * +a.X;
        res.W = b.X * -a.X;

        res.X += b.Z * +a.Y;
        res.Y += b.W * +a.Y;
        res.Z += b.X * -a.Y;
        res.W += b.Y * -a.Y;

        res.X += b.Y * -a.Z;
        res.Y += b.X * +a.Z;
        res.Z += b.W * +a.Z;
        res.W += b.Z * -a.Z;

        res.X += b.X * +a.W;
        res.Y += b.Y * +a.W;
        res.Z += b.Z * +a.W;
        res.W += b.W * +a.W;
        return res;
    }

    public static Quat operator -(Quat quaternion)
    {
        Quat quaternion2;
        quaternion2.X = -quaternion.X;
        quaternion2.Y = -quaternion.Y;
        quaternion2.Z = -quaternion.Z;
        quaternion2.W = -quaternion.W;
        return quaternion2;
    }
}

static
{
    public const float TURNS_TO_RAD = 6.28318f;
    public const float RAD_TO_TURNS = 1.0f / TURNS_TO_RAD;

    public static Vector3f AxisV3(Axis3 axis)
    {
        switch (axis)
        {
            case .X: return Vector3f(1, 0, 0);
            case .Y: return Vector3f(0, 1, 0);
            case .Z: return Vector3f(0, 0, 1);
        }
    }

    public static float AddClamp01(float dst, float delta)
    {
        return (float)Math.Clamp(dst + delta, 0.0, 1.0);
    }

    public static float Smoothstep(float t, float min = 0, float max = 1)
    {
        float tn = (float)Math.Clamp((t - min) / (max - min), 0.0, 1.0);
        return tn * tn * (3.0f - 2.0f * tn);
    }

    public static float Sign(float x)
    {
        return x < 0.0f ? -1.0f : 1.0f;
    }

    public static uint32 CeilPow2(uint32 vo)
    {
        if (vo == 0)
        {
            return 0;
        }
        uint32 v = vo;
        v -= 1;
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
        v |= v >> 8;
        v |= v >> 16;
        v += 1;
        return v;
    }

    public static float WrapFloat(float min, float max, float value)
    {
        float range = max - min;
        float offset = value - min;
        return (offset - (Math.Floor(offset / range) * range) + min);
    }

    public static float invsqrt(float x)
    {
        return 1.0f / Math.Sqrt(x);
    }

    public static float Tan(float turns)
    {
        return Math.Tan(turns * TURNS_TO_RAD);
    }
    public static float Atan2(float x, float y)
    {
        return Math.Atan2(x, y) * RAD_TO_TURNS;
    }
    public static float Atan2(Vector2f vec)
    {
        return Atan2(vec.X, vec.Y);
    }
    public static float Acos(float x)
    {
        return Math.Acos(x) * RAD_TO_TURNS;
    }


    public static (float, float) SinCos(float turns)
    {
        float rad = TURNS_TO_RAD * turns;
        // @speed add optimized function that calculates both sin & cos at once at reduced total cost
        float s = Math.Sin(rad);
        float c = Math.Cos(rad);
        return (s, c);
    }

    public static float Sin(float turns)
    {
        float rad = TURNS_TO_RAD * turns;
        return Math.Sin(rad);
    }
    public static float Cos(float turns)
    {
        float rad = TURNS_TO_RAD * turns;
        return Math.Cos(rad);
    }

    public static float Sin01(float turns)
    {
        return Sin(turns) * 0.5f + 0.5f;
    }
    public static float Cos01(float turns)
    {
        return Cos(turns) * 0.5f + 0.5f;
    }
}
