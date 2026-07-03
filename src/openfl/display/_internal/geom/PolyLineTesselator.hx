package openfl.display._internal.geom;

import openfl.display.JointStyle;
import openfl.display.CapsStyle;

class PolyLineTesselator
{
	public var vertices(default, null):Array<Float> = [];
	public var indices(default, null):Array<Int> = [];
	// public var contourInner(default, null):Array<Int> = [];
	// public var contourOuter(default, null):Array<Int> = [];
	public var numVertices(default, null):Int = 0;
	public var selfIntersecting(default, null):Bool = false;

	private var flipped:Bool = false;
	private var prevInnerIdx:Int = -1;
	private var prevCenterIdx:Int = -1;
	private var prevOuterIdx:Int = -1;
	private var curveTolerance:Float = 0.25;

	var half:Float = 0.0;
	var angleStep:Float = 0.0;
	var dxIn:Float = 0.0;
	var dyIn:Float = 0.0;
	var dxOut:Float = 0.0;
	var dyOut:Float = 0.0;
	var nxOut:Float = 0.0;
	var nyOut:Float = 0.0;
	var nxIn:Float = 0.0;
	var nyIn:Float = 0.0;
	var currX:Float = 0.0;
	var currY:Float = 0.0;

	static private inline var EPSILON:Float = 1e-6;
	static private inline var EPSILON2:Float = 1e-12;

	public function new(curveTolerance:Float = 0.25)
	{
		this.curveTolerance = curveTolerance;
	}

	public function tesselate(points:Vector<Float>, closed:Bool, thickness:Float, joints:JointStyle, caps:CapsStyle, miterLimit:Float,
			scaleMode:LineScaleMode):Void
	{
		if (vertices.length > 0) throw "PolyLineTesselator: vertices array is not empty. Create a new instance.";

		half = Math.abs(thickness) * 0.5;
		angleStep = 2 * Math.acos(Math.max(0, 1 - (curveTolerance / half)));

		var prevX:Float = 0, prevY:Float = 0;
		var nextX:Float = 0, nextY:Float = 0;
		var currIdx:Int = -1, prevIdx:Int = -1, nextIdx:Int = -1;
		var n = Std.int(points.length / 2);

		if (n < 2) return;

		var innerIsLeft:Bool = false;
		var prevInnerIsLeft:Bool = false;
		var firstInnerIsLeft:Null<Bool> = null;
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
					break;
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
				addCap(caps, innerX, innerY, currX, currY, outerX, outerY, -dxOut, -dyOut, half, innerIsLeft, false);
			}

			if (first)
			{
				// always skip first iteration otherwise dxIn and dyIn will be 0
				first = false;
				continue;
			}

			det = dxIn * dyOut - dyIn * dxOut;
			prevInnerIsLeft = innerIsLeft;
			innerIsLeft = det >= 0;
			if (firstInnerIsLeft == null) firstInnerIsLeft = innerIsLeft;

			if (prevInnerIsLeft != innerIsLeft)
			{
				var tmp = prevOuterIdx;
				prevOuterIdx = prevInnerIdx;
				prevInnerIdx = tmp;
			}

			var collinear = Math.abs(det) < EPSILON;

			if (collinear) selfIntersecting = true;
			var degenerate = false;

			if (innerIsLeft)
			{
				nxIn = -nxIn;
				nxOut = -nxOut;
				nyIn = -nyIn;
				nyOut = -nyOut;
			}

			flipped = innerIsLeft;

			var outerLX = currX + nxIn * half;
			var outerLY = currY + nyIn * half;
			var outerRX = currX + nxOut * half;
			var outerRY = currY + nyOut * half;
			var innerLX = currX - nxIn * half;
			var innerLY = currY - nyIn * half;
			var innerRX = currX - nxOut * half;
			var innerRY = currY - nyOut * half;

			// calculating miter position
			var mx = nxIn + nxOut;
			var my = nyIn + nyOut;
			var m2 = mx * mx + my * my;
			var miterX = 0.0;
			var miterY = 0.0;

			var startAng = Math.atan2(nyIn, nxIn);
			var endAng = Math.atan2(nyOut, nxOut);
			var sweep = endAng - startAng;
			if (sweep <= -Math.PI) sweep += Math.PI * 2;
			else if (sweep > Math.PI) sweep -= Math.PI * 2;

			// var isCurve = curves[currIdx];
			var isCurve = Math.abs(sweep) <= angleStep;
			var isMiter = isCurve || joints == MITER;
			var isRound = !isCurve && joints == ROUND;
			var joint:JointStyle = isMiter ? MITER : isRound ? ROUND : BEVEL;
			var miterLength = 0.0;

			if (m2 > EPSILON2)
			{
				var m = Math.sqrt(m2);
				var dot = __clamp(dxIn * dxOut + dyIn * dyOut, -1.0, 1.0);
				miterLength = 1 / Math.sqrt((1 + dot) * 0.5);
				mx /= m;
				my /= m;

				// The outer edge segment
				var prevOuterLX = prevX + nxIn * half;
				var prevOuterLY = prevY + nyIn * half;
				var prevOuterRX = prevX - nxIn * half;
				var prevOuterRY = prevY - nyIn * half;
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
					// if (t > 0 && u >= 0 && u <= 1) {
					if (miterLength > (t / half))
					{
						degenerate = true;
					}
					// }
				}

				if (miterLength > miterLimit && joint == MITER) joint = BEVEL;

				if (!degenerate)
				{
					innerLX = innerRX = currX - mx * miterLength * half;
					innerLY = innerRY = currY - my * miterLength * half;
				}

				miterX = currX + mx * miterLength * half;
				miterY = currY + my * miterLength * half;
			}

			if (degenerate)
			{
				selfIntersecting = true;
				addVertices(innerLX, innerLY, currX, currY, outerLX, outerLY);

				switch (joint)
				{
					case MITER:
						addVertices(innerLX, innerLY, currX, currY, miterX, miterY);
					case ROUND:
						addRoundJoint();
					default:
				}

				addVertices(innerRX, innerRY, currX, currY, outerRX, outerRY);
			}
			else
			{
				switch (joint)
				{
					case MITER:
						addVertices(innerLX, innerLY, currX, currY, miterX, miterY);
					case ROUND:
						addVertices(innerLX, innerLY, currX, currY, outerLX, outerLY);
						addRoundJoint();
					default:
						addVertices(innerLX, innerLY, currX, currY, outerLX, outerLY);
						var prevPrevOuterIdx = prevOuterIdx;
						prevOuterIdx = addVertex(outerRX, outerRY, prevOuterIdx);
						// addContourIdx(prevOuterIdx);
						addTriangle(prevOuterIdx, prevPrevOuterIdx, prevInnerIdx);
				}
			}
		}

		flipped = false;

		if (closed)
		{
			#if openfl_enable_gl_polyline_spine
			var l0 = 0;
			var l1 = prevInnerIdx;
			var c0 = 1;
			var c1 = prevCenterIdx;
			var r0 = 2;
			var r1 = prevOuterIdx;
			if (firstInnerIsLeft != innerIsLeft)
			{
				var temp = r1;
				r1 = l1;
				l1 = temp;
			}
			addQuad(c0, l0, l1, c1);
			addQuad(c1, r1, r0, c0);
			#else
			var l0 = 0;
			var l1 = prevInnerIdx;
			var r0 = 1;
			var r1 = prevOuterIdx;
			if (firstInnerIsLeft != innerIsLeft)
			{
				var tmp = l1;
				l1 = r1;
				r1 = tmp;
			}
			addQuad(r1, r0, l0, l1);
			#end

			// contourOuter.reverse();
		}
		else
		{
			var innerX = nextX - nxOut * half;
			var innerY = nextY - nyOut * half;
			var outerX = nextX + nxOut * half;
			var outerY = nextY + nyOut * half;
			addCap(caps, innerX, innerY, nextX, nextY, outerX, outerY, dxOut, dyOut, half, innerIsLeft, true);

			// for (i in contourOuter)
			// 	contourInner.push(i);
			// contourOuter = null;
		}

		// trace("selfIntersecting", selfIntersecting);
	}

	function addRoundJoint()
	{
		var anchorIdx = #if openfl_enable_gl_polyline_spine prevCenterIdx #else prevInnerIdx #end;
		var startAng = Math.atan2(nyIn, nxIn);
		var endAng = Math.atan2(nyOut, nxOut);
		var sweep = endAng - startAng;
		if (sweep <= -Math.PI) sweep += Math.PI * 2;
		else if (sweep > Math.PI) sweep -= Math.PI * 2;
		var steps = calculateArcSteps(sweep) - 1;
		for (k in 0...steps)
		{
			var t = (k + 1) / steps;
			var ang = startAng + sweep * t;
			var ax = currX + Math.cos(ang) * half;
			var ay = currY + Math.sin(ang) * half;
			var arcIdx = addVertex(ax, ay, prevOuterIdx);
			// addContourIdx(arcIdx);
			addTriangle(anchorIdx, arcIdx, prevOuterIdx);
			prevOuterIdx = arcIdx;
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

		flipped = innerIsLeft;
		// if (isEnd) reverseTriangles = !reverseTriangles;
		addVertices(innerX, innerY, centerX, centerY, outerX, outerY);

		if (caps == SQUARE)
		{
			#if openfl_enable_gl_polyline_spine
			addTriangle(prevInnerIdx, prevCenterIdx, prevOuterIdx);
			#end
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
			var anchorIdx = #if openfl_enable_gl_polyline_spine prevCenterIdx #else endIdx #end;
			var prevArcIdx = startIdx;
			var steps = calculateArcSteps(Math.PI);
			for (k in 0...(steps - 1))
			{
				var t = (k + 1) / steps;
				if (isEnd) t = 1 - t;
				var ang = start + Math.PI * t;
				var ax = centerX + Math.cos(ang) * half;
				var ay = centerY + Math.sin(ang) * half;
				var arcIdx = addVertex(ax, ay, prevArcIdx);
				// addContourIdx(arcIdx);
				addTriangle(anchorIdx, prevArcIdx, arcIdx);
				prevArcIdx = arcIdx;
			}
			#if openfl_enable_gl_polyline_spine
			addTriangle(prevCenterIdx, prevArcIdx, endIdx);
			#end
		}
	}

	private function addVertex(x:Float, y:Float, prevIdx:Int):Int
	{
		// if (prevIdx != -1)
		// {
		// 	var prevX = vertices[prevIdx * 2];
		// 	var prevY = vertices[prevIdx * 2 + 1];
		// 	if (prevX == x && prevY == y) return prevIdx;
		// }
		vertices.push(x);
		vertices.push(y);
		numVertices++;
		return numVertices - 1;
	}

	// public function getContours()
	// {
	// 	var results = [getContour(contourInner)];
	// 	if (contourOuter != null) results.push(getContour(contourOuter));
	// 	return results;
	// }
	// function getContour(indices:Array<Int>):Array<Float>
	// {
	// 	var contour = new haxe.ds.Vector<Float>(indices.length * 2);
	// 	for (i in 0...indices.length)
	// 	{
	// 		contour[i * 2] = vertices[indices[i] * 2];
	// 		contour[i * 2 + 1] = vertices[indices[i] * 2 + 1];
	// 	}
	// 	return cast contour;
	// }

	private function addVertices(innerX:Float, innerY:Float, centerX:Float, centerY:Float, outerX:Float, outerY:Float):Void
	{
		var isFirst = vertices.length == 0;
		var prevPrevInner = prevInnerIdx;
		var prevPrevOuter = prevOuterIdx;
		#if openfl_enable_gl_polyline_spine
		var prevPrevCenter = prevCenterIdx;
		prevInnerIdx = addVertex(innerX, innerY, prevInnerIdx);
		prevCenterIdx = addVertex(centerX, centerY, prevCenterIdx);
		prevOuterIdx = addVertex(outerX, outerY, prevOuterIdx);

		if (!isFirst)
		{
			addQuad(prevPrevCenter, prevPrevInner, prevInnerIdx, prevCenterIdx);
			addQuad(prevCenterIdx, prevOuterIdx, prevPrevOuter, prevPrevCenter);
		}
		#else
		prevInnerIdx = addVertex(innerX, innerY, prevInnerIdx);
		prevOuterIdx = addVertex(outerX, outerY, prevOuterIdx);
		if (!isFirst)
		{
			addQuad(prevPrevInner, prevInnerIdx, prevOuterIdx, prevPrevOuter);
		}
		#end

		// if (flipped)
		// {
		// 	contourOuter.push(prevInnerIdx);
		// 	contourInner.push(prevOuterIdx);
		// }
		// else
		// {
		// 	contourInner.push(prevInnerIdx);
		// 	contourOuter.push(prevOuterIdx);
		// }
	}

	// private inline function addContourIdx(idx:Int):Void
	// {
	// 	if (flipped) contourInner.push(idx);
	// 	else
	// 		contourOuter.push(idx);
	// }

	private function addTriangle(i0:Int, i1:Int, i2:Int):Void
	{
		if (flipped)
		{
			var tmp = i0;
			i0 = i2;
			i2 = tmp;
		}
		var x0 = vertices[i0 * 2];
		var y0 = vertices[i0 * 2 + 1];
		var x1 = vertices[i1 * 2];
		var y1 = vertices[i1 * 2 + 1];
		var x2 = vertices[i2 * 2];
		var y2 = vertices[i2 * 2 + 1];
		var signedArea = __cross(x0, y0, x1, y1, x2, y2);
		if (Math.abs(signedArea) >= EPSILON)
		{
			indices.push(i0);
			indices.push(i1);
			indices.push(i2);
			if (signedArea < 0)
			{
				// not sure if this is safe to assume
				selfIntersecting = true;
			}
		}
	}

	private function addQuad(i0:Int, i1:Int, i2:Int, i3:Int):Void
	{
		addTriangle(i0, i1, i2);
		addTriangle(i0, i2, i3);
	}

	private inline function calculateArcSteps(angle:Float)
	{
		var steps = Math.ceil(Math.abs(angle) / angleStep);
		return steps < 2 ? 2 : steps;
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
