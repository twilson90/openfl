package openfl.display._internal.geom;

import openfl.display.JointStyle;
import openfl.display.CapsStyle;

class PolyLineTesselator
{
	public var vertices(default, null):Array<Float> = [];
	public var indices(default, null):Array<Int> = [];
	public var numVertices(default, null):Int = 0;
	public var selfIntersecting(default, null):Bool = false;

	private var reverseTriangles:Bool = false;
	private var prevInnerIdx:Int = -1;
	private var prevCenterIdx:Int = -1;
	private var prevOuterIdx:Int = -1;
	private var hasSpine:Bool = false;
	private var curveTolerance:Float = 0.25;

	static private inline var EPSILON:Float = 1e-6;
	static private inline var EPSILON2:Float = 1e-12;

	public function new(curveTolerance:Float = 0.25, hasSpine:Bool = false)
	{
		this.curveTolerance = curveTolerance;
		this.hasSpine = hasSpine;
	}

	public function tesselate(points:Vector<Float>, curves:Vector<Bool>, closed:Bool, thickness:Float, joint:JointStyle, caps:CapsStyle, miterLimit:Float,
			scaleMode:LineScaleMode):Void
	{
		if (vertices.length > 0) throw "PolyLineTesselator: vertices array is not empty. Create a new instance.";

		var half = Math.abs(thickness) * 0.5;
		var n = Std.int(points.length / 2);

		if (n < 2) return;

		var dxIn:Float = 0.0, dyIn:Float = 0.0;
		var dxOut:Float = 0.0, dyOut:Float = 0.0;
		var nxOut:Float = 0.0, nyOut:Float = 0.0;
		var nxIn:Float = 0.0, nyIn:Float = 0.0;
		var prevX:Float = 0, prevY:Float = 0;
		var currX:Float = 0, currY:Float = 0;
		var nextX:Float = 0, nextY:Float = 0;

		var currIdx:Int = -1,
			prevIdx:Int = -1,
			nextIdx:Int = -1,
			prevOuterLIdx:Int = -1,
			prevOuterRIdx:Int = -1;
		var innerIsLeft:Bool = false;
		var prevInnerIsLeft:Bool = false;
		var det:Float = 0.0;

		var len2:Float = 0;
		var i = 0;
		var n1 = closed ? n + 1 : n - 1;
		var first = true;
		while (i < n1)
		{
			prevIdx = currIdx;
			prevX = currX;
			prevY = currY;
			currIdx = i % n;
			currX = points[currIdx * 2];
			currY = points[currIdx * 2 + 1];
			dxIn = dxOut;
			dyIn = dyOut;
			while (i < n1)
			{
				nextIdx = ++i % n;
				nextX = points[nextIdx * 2];
				nextY = points[nextIdx * 2 + 1];
				dxOut = nextX - currX;
				dyOut = nextY - currY;
				len2 = dxOut * dxOut + dyOut * dyOut;
				if (len2 > EPSILON2)
				{
					var len = Math.sqrt(len2);
					dxOut /= len;
					dyOut /= len;
					if (first) break;
					det = dxIn * dyOut - dyIn * dxOut;
					if (Math.abs(det) > EPSILON)
					{
						break;
					}
				}
			}
			if (i > n1) break;

			nxOut = -dyOut;
			nyOut = dxOut;
			nxIn = -dyIn;
			nyIn = dxIn;

			if (!closed && first)
			{
				var innerX = currX - nxOut * half;
				var innerY = currY - nyOut * half;
				var outerX = currX + nxOut * half;
				var outerY = currY + nyOut * half;
				prevOuterLIdx = 0;
				addCap(caps, innerX, innerY, currX, currY, outerX, outerY, -dxOut, -dyOut, half, innerIsLeft, false);
				prevOuterRIdx = prevOuterIdx;
			}

			if (first)
			{
				// always skip first iteration otherwise dxIn and dyIn will be 0
				first = false;
				continue;
			}

			var isCurve = curves[currIdx];
			var isRound = !isCurve && joint == ROUND;
			var isMiter = isCurve || joint == MITER;
			var degenerateJoin = false;
			prevInnerIsLeft = innerIsLeft;
			innerIsLeft = det > 0;

			if (prevInnerIsLeft != innerIsLeft)
			{
				var tmp = prevOuterIdx;
				prevOuterIdx = prevInnerIdx;
				prevInnerIdx = tmp;
				tmp = prevOuterLIdx;
				prevOuterLIdx = prevOuterRIdx;
				prevOuterRIdx = tmp;
			}

			var collinear = Math.abs(det) < EPSILON;

			if (innerIsLeft)
			{
				nxIn = -nxIn;
				nxOut = -nxOut;
				nyIn = -nyIn;
				nyOut = -nyOut;
			}

			var outerLX = currX + nxIn * half;
			var outerLY = currY + nyIn * half;
			var outerRX = currX + nxOut * half;
			var outerRY = currY + nyOut * half;
			var innerOrigX = currX - nxOut * half;
			var innerOrigY = currY - nyOut * half;
			var innerX = innerOrigX;
			var innerY = innerOrigY;
			var prevInnerX = vertices[prevInnerIdx * 2];
			var prevInnerY = vertices[prevInnerIdx * 2 + 1];
			var prevOuterLX = vertices[prevOuterLIdx * 2];
			var prevOuterLY = vertices[prevOuterLIdx * 2 + 1];
			var prevOuterRX = vertices[prevOuterRIdx * 2];
			var prevOuterRY = vertices[prevOuterRIdx * 2 + 1];
			// var prevOuterLX = prevX + nxIn * half;
			// var prevOuterLY = prevY + nyIn * half;
			// var prevOuterRX = prevX - nxIn * half;
			// var prevOuterRY = prevY - nyIn * half;

			// calculating miter position
			var mx = nxIn + nxOut;
			var my = nyIn + nyOut;
			var m2 = mx * mx + my * my;
			if (m2 > EPSILON2)
			{
				var m = Math.sqrt(m2);
				var dot = __clamp(dxIn * dxOut + dyIn * dyOut, -1.0, 1.0);
				var miterLength = 1 / Math.sqrt((1 + dot) * 0.5);
				mx /= m;
				my /= m;

				// The outer edge segment
				var ax = prevOuterRX - prevOuterLX;
				var ay = prevOuterRY - prevOuterLY;
				var bx = prevOuterLX - currX;
				var by = prevOuterLY - currY;
				var cx = -mx;
				var cy = -my;

				var denom = (cx * ay) - (cy * ax);
				if (Math.abs(denom) > EPSILON)
				{
					// Intersection distance t along inward ray
					var t = (bx * ay - by * ax) / denom;
					var u = (bx * cy - by * cx) / denom;
					if (t > 0 && u >= 0 && u <= 1)
					{
						var maxDist = t; // max allowed distance from curr to inner point
						var maxMiterLength = maxDist / half; // convert to miter length factor
						if (miterLength > maxMiterLength)
						{
							// selfIntersecting = true;
							degenerateJoin = true;
						}
					}
				}

				if (miterLength > miterLimit) isMiter = false;

				if (!degenerateJoin)
				{
					innerX = currX - mx * miterLength * half;
					innerY = currY - my * miterLength * half;

					if (isMiter)
					{
						outerLX = outerRX = currX + mx * miterLength * half;
						outerLY = outerRY = currY + my * miterLength * half;
					}
				}
			}

			reverseTriangles = innerIsLeft;
			// trace('${i} / ${n1} -- X:${currX}, Y:${currY}, DEG: ${degenerateJoin}');

			// var ccw = __cross(innerX, innerY, currX, currY, outerLX, outerLY) < 0;
			// if (!ccw && !innerIsLeft || ccw && innerIsLeft)
			// {
			// 	degenerateJoin = true;
			// 	trace(i);
			// }

			// if (degenerateJoin)
			// {
			// 	var lx1 = currX - nxIn * half;
			// 	var ly1 = currY - nyIn * half;
			// 	var rx1 = currX + nxIn * half;
			// 	var ry1 = currY + nyIn * half;
			// 	// trace(lx1, ly1, rx1, ry1);
			// 	addVertices(lx1, ly1, currX, currY, rx1, ry1);
			// 	var lx2 = currX - nxOut * half;
			// 	var ly2 = currY - nyOut * half;
			// 	var rx2 = currX + nxOut * half;
			// 	var ry2 = currY + nyOut * half;
			// 	// trace(lx2, ly2, rx2, ry2);
			// 	addVertices(lx2, ly2, currX, currY, rx2, ry2);
			// 	prevOuterLIdx = prevOuterIdx;
			// }
			// else
			// {
			addVertices(innerX, innerY, currX, currY, outerLX, outerLY);
			prevOuterLIdx = prevOuterIdx;

			if (!isMiter && !collinear)
			{
				var anchorIdx = hasSpine ? prevCenterIdx : prevInnerIdx;
				if (isRound)
				{
					var startAng = Math.atan2(nyIn, nxIn);
					var endAng = Math.atan2(nyOut, nxOut);
					var sweep = endAng - startAng;
					if (sweep <= -Math.PI) sweep += Math.PI * 2;
					else if (sweep > Math.PI) sweep -= Math.PI * 2;
					var steps = calculateArcSteps(half, sweep) - 1;
					for (k in 0...steps)
					{
						var t = (k + 1) / steps;
						var ang = startAng + sweep * t;
						var ax = currX + Math.cos(ang) * half;
						var ay = currY + Math.sin(ang) * half;
						var arcIdx = addVertex(ax, ay);
						addTriangle(anchorIdx, arcIdx, prevOuterIdx);
						prevOuterIdx = arcIdx;
					}
				}
				else
				{
					prevOuterIdx = addVertex(outerRX, outerRY);
					addTriangle(anchorIdx, prevOuterIdx, prevOuterLIdx);
				}
			}
		}
		prevOuterRIdx = prevOuterIdx;
		// }

		reverseTriangles = false;

		if (closed)
		{
			if (hasSpine)
			{
				addQuad(prevCenterIdx, 1, 0, prevInnerIdx);
				addQuad(1, 2, prevOuterIdx, prevCenterIdx);
			}
			else
			{
				addQuad(prevOuterIdx, 1, 0, prevInnerIdx);
			}
		}
		else
		{
			var innerX = nextX - nxOut * half;
			var innerY = nextY - nyOut * half;
			var outerX = nextX + nxOut * half;
			var outerY = nextY + nyOut * half;
			addCap(caps, innerX, innerY, nextX, nextY, outerX, outerY, dxOut, dyOut, half, innerIsLeft, true);
		}
	}

	function addCap(caps:CapsStyle, innerX:Float, innerY:Float, centerX:Float, centerY:Float, outerX:Float, outerY:Float, dx:Float, dy:Float, half:Float,
			innerIsLeft:Bool, isEnd:Bool):Void
	{
		var nx = -dy;
		var ny = dx;

		if (caps == SQUARE)
		{
			innerX += dx * half;
			innerY += dy * half;
			outerX += dx * half;
			outerY += dy * half;
		}

		addVertices(innerX, innerY, centerX, centerY, outerX, outerY);
		reverseTriangles = isEnd;

		if (caps == SQUARE)
		{
			if (hasSpine) addTriangle(prevInnerIdx, prevCenterIdx, prevOuterIdx);
		}
		else if (caps == ROUND)
		{
			var start = Math.atan2(-ny, -nx);
			var startIdx:Int;
			var endIdx:Int;
			if (innerIsLeft)
			{
				startIdx = prevInnerIdx;
				endIdx = prevOuterIdx;
			}
			else
			{
				startIdx = prevOuterIdx;
				endIdx = prevInnerIdx;
			}
			var anchorIdx = hasSpine ? prevCenterIdx : endIdx;
			var prevArcIdx = startIdx;
			var steps = calculateArcSteps(half, Math.PI);
			for (k in 0...(steps - 1))
			{
				var t = (k + 1) / steps;
				if (isEnd) t = 1 - t;
				var ang = start + Math.PI * t;
				var ax = centerX + Math.cos(ang) * half;
				var ay = centerY + Math.sin(ang) * half;
				var arc = addVertex(ax, ay);
				addTriangle(anchorIdx, prevArcIdx, arc);
				prevArcIdx = arc;
			}
			if (hasSpine)
			{
				addTriangle(prevCenterIdx, prevArcIdx, endIdx);
			}
		}
	}

	private function addVertex(x:Float, y:Float):Int
	{
		vertices.push(x);
		vertices.push(y);
		numVertices++;
		return numVertices - 1;
	}

	private function addVertices(innerX:Float, innerY:Float, centerX:Float, centerY:Float, outerX:Float, outerY:Float):Void
	{
		var isFirst = vertices.length == 0;
		var prevPrevInner = prevInnerIdx;
		var prevPrevOuter = prevOuterIdx;
		if (hasSpine)
		{
			var prevPrevCenter = prevCenterIdx;
			prevInnerIdx = addVertex(innerX, innerY);
			prevCenterIdx = addVertex(centerX, centerY);
			prevOuterIdx = addVertex(outerX, outerY);
			if (!isFirst)
			{
				addQuad(prevPrevCenter, prevPrevInner, prevInnerIdx, prevCenterIdx);
				addQuad(prevCenterIdx, prevOuterIdx, prevPrevOuter, prevPrevCenter);
			}
		}
		else
		{
			prevInnerIdx = addVertex(innerX, innerY);
			prevOuterIdx = addVertex(outerX, outerY);
			if (!isFirst)
			{
				addQuad(prevPrevInner, prevInnerIdx, prevOuterIdx, prevPrevOuter);
			}
		}
	}

	private inline function addTriangle(i0:Int, i1:Int, i2:Int):Void
	{
		if (reverseTriangles)
		{
			var tmp = i0;
			i0 = i2;
			i2 = tmp;
		}

		indices.push(i0);
		indices.push(i1);
		indices.push(i2);

		var x0 = vertices[i0 * 2];
		var y0 = vertices[i0 * 2 + 1];
		var x1 = vertices[i1 * 2];
		var y1 = vertices[i1 * 2 + 1];
		var x2 = vertices[i2 * 2];
		var y2 = vertices[i2 * 2 + 1];
		var signedArea = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
		var ccw = signedArea > EPSILON;
		if (!ccw)
		{
			// not sure if this is safe to assume
			selfIntersecting = true;
		}
	}

	private inline function addQuad(i0:Int, i1:Int, i2:Int, i3:Int):Void
	{
		addTriangle(i0, i1, i2);
		addTriangle(i0, i2, i3);
	}

	private inline function calculateArcSteps(half:Float, angle:Float)
	{
		var maxStep = 2 * Math.acos(Math.max(0, 1 - curveTolerance / half));
		var steps = Math.ceil(Math.abs(angle) / maxStep);
		if (steps < 2) return 2;
		return steps;
	}

	private static inline function __clamp(x:Float, min:Float, max:Float):Float
	{
		return Math.max(min, Math.min(max, x));
	}

	private static inline function __cross(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Float
	{
		return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	}
}
