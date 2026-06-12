package openfl.display._internal.geom;

import openfl.display.JointStyle;
import openfl.display.CapsStyle;

class PolyLineTesselator
{
	public var curveTolerance:Float = 0.25;
	public var vertices(default, null):Array<Float> = [];
	public var indices(default, null):Array<Int> = [];

	public var numVertices(default, null):Int = 0;
	public var prevL(default, null):Int = -1;
	public var prevR(default, null):Int = -1;

	static private inline var EPSILON:Float = 1e-6;
	static private inline var EPSILON2:Float = 1e-12;

	public function new(curveTolerance:Float = 0.25)
	{
		this.curveTolerance = curveTolerance;
	}

	public function tesselate(points:Vector<Float>, curves:Vector<Bool>, closed:Bool, thickness:Float, joint:JointStyle, caps:CapsStyle, miterLimit:Float,
			scaleMode:LineScaleMode):Void
	{
		var half = Math.abs(thickness) * 0.5;
		var n = Std.int(points.length / 2);

		if (n < 2) return;

		var dxIn:Float = 0.0, dyIn:Float = 0.0;
		var dxOut:Float = 0.0, dyOut:Float = 0.0;
		var nxOut:Float = 0.0, nyOut:Float = 0.0;
		var nxIn:Float = 0.0, nyIn:Float = 0.0;
		var currX:Float = 0, currY:Float = 0;
		var nextX:Float = 0, nextY:Float = 0;
		var currIdx:Int = -1, nextIdx:Int = -1;

		var i = 0;
		var j = 0;
		var n1 = closed ? n + 1 : n - 1;
		while (i < n1)
		{
			currIdx = i;
			currX = points[currIdx * 2];
			currY = points[currIdx * 2 + 1];
			var len2:Float = 0, dx:Float = 0, dy:Float = 0;
			while (true)
			{
				nextIdx = (i + 1) % n;
				nextX = points[nextIdx * 2];
				nextY = points[nextIdx * 2 + 1];
				dx = nextX - currX;
				dy = nextY - currY;
				len2 = dx * dx + dy * dy;
				if (len2 > EPSILON2) break;
				i++;
			}

			var len = Math.sqrt(len2);
			dx /= len;
			dy /= len;

			dxIn = dxOut;
			dyIn = dyOut;
			dxOut = dx;
			dyOut = dy;

			nxOut = -dyOut;
			nyOut = dxOut;
			nxIn = -dyIn;
			nyIn = dxIn;

			var dot = __clamp(dxIn * dxOut + dyIn * dyOut, -1.0, 1.0);
			var det = dxIn * dyOut - dyIn * dxOut;
			var innerIsLeft = det > 0;

			if (innerIsLeft)
			{
				nxIn = -nxIn;
				nyIn = -nyIn;
				nxOut = -nxOut;
				nyOut = -nyOut;
			}

			var l0x = currX + nxOut * half;
			var l0y = currY + nyOut * half;

			var r0x = currX - nxOut * half;
			var r0y = currY - nyOut * half;

			var l1x = nextX + nxOut * half;
			var l1y = nextY + nyOut * half;

			var r1x = nextX - nxOut * half;
			var r1y = nextY - nyOut * half;

			if (j > 0)
			{
				var currJoint = curves[currIdx] ? BEVEL : joint;
				addJoint(currJoint, currX, currY, nxOut, nyOut, nxIn, nyIn, half, dot, miterLimit);
			}

			if (j == 0 && !closed)
			{
				addCap(caps, currX, currY, dxOut, dyOut, half);
			}

			if (i < n)
			{
				addSegmentQuad(l0x, l0y, r0x, r0y, l1x, l1y, r1x, r1y);
			}

			j++;
			i++;
		}

		if (!closed)
		{
			addCap(caps, nextX, nextY, -dxOut, -dyOut, half);
		}
	}

	function addJoint(currJoint:JointStyle, x:Float, y:Float, nxOut:Float, nyOut:Float, nxIn:Float, nyIn:Float, half:Float, dot:Float, miterLimit:Float)
	{
		var c = addVertex(x, y);

		switch (currJoint)
		{
			case BEVEL:
				addVertexPair(x + nxIn * half, y + nyIn * half, x + nxOut * half, y + nyOut * half);
				addTriangle(c, prevL, prevR);

			case MITER:
				var miterLength = 1 / Math.sqrt((1 + dot) * 0.5);
				if (miterLength > miterLimit)
				{
					addVertexPair(x + nxIn * half, y + nyIn * half, x + nxOut * half, y + nyOut * half);
					addTriangle(c, prevL, prevR);
				}
				else
				{
					var mX = nxIn + nxOut;
					var mY = nyIn + nyOut;
					var mLen = Math.sqrt(mX * mX + mY * mY);

					if (mLen > EPSILON)
					{
						mX /= mLen;
						mY /= mLen;

						var miterLength = 1 / Math.sqrt((1 + dot) / 2);

						var mx = x + mX * half * miterLength;
						var my = y + mY * half * miterLength;

						addVertexPair(x + nxIn * half, y + nyIn * half, x + nxOut * half, y + nyOut * half);
						var m = addVertex(mx, my);

						addTriangle(c, prevL, m);
						addTriangle(c, m, prevR);
					}
				}
			case ROUND:
				var startAng = Math.atan2(nyIn, nxIn);
				var endAng = Math.atan2(nyOut, nxOut);
				var sweep = endAng - startAng;
				if (sweep <= -Math.PI) sweep += Math.PI * 2;
				else if (sweep > Math.PI) sweep -= Math.PI * 2;
				var steps = calculateArcSteps(half, sweep);
				var prevArc = addVertex(x + Math.cos(startAng) * half, y + Math.sin(startAng) * half);
				for (k in 1...steps + 1)
				{
					var t = k / steps;
					var ang = startAng + sweep * t;
					var ax = x + Math.cos(ang) * half;
					var ay = y + Math.sin(ang) * half;
					var arc = addVertex(ax, ay);
					addTriangle(c, prevArc, arc);
					prevArc = arc;
				}
				prevL = prevArc;
		}
	}

	function addCap(caps:CapsStyle, px:Float, py:Float, dx:Float, dy:Float, half:Float):Void
	{
		if (caps == NONE) return;

		var nx = -dy;
		var ny = dx;
		var l0x = px + nx * half;
		var l0y = py + ny * half;
		var r0x = px - nx * half;
		var r0y = py - ny * half;

		switch (caps)
		{
			case SQUARE:
				// extend along segment by half
				var l1x = l0x - dx * half;
				var l1y = l0y - dy * half;
				var r1x = r0x - dx * half;
				var r1y = r0y - dy * half;
				addSegmentQuad(l0x, l0y, r0x, r0y, l1x, l1y, r1x, r1y);

			case ROUND:
				var steps = calculateArcSteps(half, Math.PI);
				var startAng = Math.atan2(ny, nx);

				var leftIdx = addVertex(l0x, l0y);
				var rightIdx = addVertex(r0x, r0y);
				var prevIdx = leftIdx;
				for (k in 1...steps + 1)
				{
					var t = k / steps;
					var ang = startAng + t * Math.PI;
					var x = px + half * Math.cos(ang);
					var y = py + half * Math.sin(ang);
					var currIdx = addVertex(x, y);
					addTriangle(rightIdx, prevIdx, currIdx);
					prevIdx = currIdx;
				}
			default:
		}
	}

	private function addVertexPair(lx:Float, ly:Float, rx:Float, ry:Float)
	{
		prevL = addVertex(lx, ly);
		prevR = addVertex(rx, ry);
	}

	private inline function addSegmentQuad(l0x:Float, l0y:Float, r0x:Float, r0y:Float, l1x:Float, l1y:Float, r1x:Float, r1y:Float):Void
	{
		addVertexPair(l0x, l0y, r0x, r0y);
		var prevPrevL = prevL;
		var prevPrevR = prevR;
		addVertexPair(l1x, l1y, r1x, r1y);
		addTriangle(prevPrevL, prevPrevR, prevL);
		addTriangle(prevL, prevPrevR, prevR);
	}

	private inline function addVertex(x:Float, y:Float):Int
	{
		vertices.push(x);
		vertices.push(y);
		numVertices++;
		return numVertices - 1;
	}

	private inline function addTriangle(i0:Int, i1:Int, i2:Int):Void
	{
		indices.push(i0);
		indices.push(i1);
		indices.push(i2);
	}

	private inline function calculateArcSteps(half:Float, angle:Float)
	{
		var maxStep = 2 * Math.acos(Math.max(0, 1 - curveTolerance / half));
		var steps = Math.ceil(Math.abs(angle) / maxStep);
		if (steps < 1) return 1;
		return steps;
	}

	private static inline function __clamp(x:Float, min:Float, max:Float):Float
	{
		return Math.max(min, Math.min(max, x));
	}
}
