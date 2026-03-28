package openfl.display._internal.geom;

import openfl.display.JointStyle;
import openfl.display.CapsStyle;
import openfl.utils.ArrayUtil;

class PolyLineTesselator
{
	public var curveTolerance:Float = 0.25;
	public var vertices:Vector<Float> = new Vector<Float>();
	public var indices:Vector<Int> = new Vector<Int>();

	private var numVertices:Int = 0;
	private var points:Vector<Float> = new Vector<Float>();
	private var directions:Vector<Float> = new Vector<Float>();
	private var curve:Vector<Bool> = new Vector<Bool>();

	private var prevL:Int = -1;
	private var prevR:Int = -1;

	static private inline var EPSILON:Float = 1e-6;
	static private inline var EPSILON2:Float = 1e-12;

	public function new(curveTolerance:Float = 0.25)
	{
		this.curveTolerance = curveTolerance;
	}

	public function reset()
	{
		points.length = 0;
		curve.length = 0;
		vertices.length = 0;
		indices.length = 0;
		numVertices = 0;
		prevL = -1;
		prevR = -1;
	}

	public function addPoint(x:Float, y:Float, isCurve:Bool = false)
	{
		var n = Std.int(points.length / 2);

		// first point
		if (n == 0)
		{
			points.push(x);
			points.push(y);
			curve.push(isCurve);
			return;
		}

		// previous point
		var bx = points[(n - 1) * 2];
		var by = points[(n - 1) * 2 + 1];

		// duplicate test
		var dx = x - bx;
		var dy = y - by;
		if ((dx * dx + dy * dy) < EPSILON2) return;

		// only two points so far
		if (n == 1)
		{
			points.push(x);
			points.push(y);
			curve.push(isCurve);
			return;
		}

		// A-B-C test
		var ax = points[(n - 2) * 2];
		var ay = points[(n - 2) * 2 + 1];
		var dx1 = bx - ax;
		var dy1 = by - ay;
		var dx2 = x - bx;
		var dy2 = y - by;
		var c = cross(dx1, dy1, dx2, dy2);

		// collinear → collapse B
		if (Math.abs(c) < EPSILON)
		{
			points[(n - 1) * 2] = x;
			points[(n - 1) * 2 + 1] = y;
			curve[n - 1] = isCurve;
			return;
		}

		// otherwise add
		points.push(x);
		points.push(y);
		curve.push(isCurve);
	}

	private inline function finalizePoints(closed:Bool)
	{
		var n = Std.int(points.length / 2);
		if (n < 2) return;

		if (closed)
		{
			var x0 = points[0];
			var y0 = points[1];

			var xn = points[(n - 1) * 2];
			var yn = points[(n - 1) * 2 + 1];

			var dx = xn - x0;
			var dy = yn - y0;

			if (dx * dx + dy * dy < EPSILON2)
			{
				points.length -= 2;
				curve.length -= 1;
			}
		}

		var area = 0.0;

		directions.length = points.length;

		var j:Int, currX:Float, currY:Float, nextX:Float, nextY:Float, dx:Float, dy:Float, len:Float;

		for (i in 0...n)
		{
			j = (i + 1) % n;
			currX = points[i * 2];
			currY = points[i * 2 + 1];
			nextX = points[j * 2];
			nextY = points[j * 2 + 1];

			area += currX * nextY - nextX * currY;
		}

		area /= 2.0;

		if (area < 0)
		{
			// Currently CW → reverse to make CCW
			reversePoints(points);
			curve.reverse();
		}

		for (i in 0...n)
		{
			j = (i + 1) % n;
			currX = points[i * 2];
			currY = points[i * 2 + 1];
			nextX = points[j * 2];
			nextY = points[j * 2 + 1];

			// outgoing vector
			dx = nextX - currX;
			dy = nextY - currY;
			len = Math.sqrt(dx * dx + dy * dy);
			dx /= len;
			dy /= len;

			directions[i * 2] = dx;
			directions[i * 2 + 1] = dy;
		}
	}

	public function addPoints(points:Vector<Float>, curve:Vector<Bool>)
	{
		var n = Std.int(points.length / 2);
		for (i in 0...n)
		{
			addPoint(points[i * 2], points[i * 2 + 1], curve[i]);
		}
	}

	public function tesselate(closed:Bool, thickness:Float, joint:JointStyle, caps:CapsStyle, miterLimit:Float, scaleMode:LineScaleMode):Void
	{
		finalizePoints(closed);

		var half = Math.abs(thickness) * 0.5;
		var n = Std.int(points.length / 2);

		if (n < 2) return;

		var segmentCount = closed ? n : n - 1;
		var firstL = -1;
		var firstR = -1;

		for (i in 0...segmentCount)
		{
			var prevIdx = (i - 1 + n) % n;
			var currIdx = i;
			var nextIdx = (i + 1) % n;

			var currX = points[currIdx * 2];
			var currY = points[currIdx * 2 + 1];
			var nextX = points[nextIdx * 2];
			var nextY = points[nextIdx * 2 + 1];
			var prevX = points[prevIdx * 2];
			var prevY = points[prevIdx * 2 + 1];

			// outgoing
			var dxOut = directions[currIdx * 2];
			var dyOut = directions[currIdx * 2 + 1];
			var nxOut = -dyOut;
			var nyOut = dxOut;

			// incoming
			var dxIn = directions[prevIdx * 2];
			var dyIn = directions[prevIdx * 2 + 1];
			var nxIn = -dyIn;
			var nyIn = dxIn;

			var dot = clamp(dxIn * dxOut + dyIn * dyOut, -1.0, 1.0);
			var det = dxIn * dyOut - dyIn * dxOut;
			var innerIsLeft = det > 0;

			// var currIsCurve = curve[currIdx];
			// var nextIsCurve = curve[nextIdx];

			// if (currIsCurve || nextIsCurve)
			// {
			// 	var mx = nxIn + nxOut;
			// 	var my = nyIn + nyOut;
			// 	var mLen = Math.sqrt(mx * mx + my * my);
			// 	mx /= mLen;
			// 	my /= mLen;

			// 	var miterLength = 1 / Math.sqrt((1 + dot) * 0.5);

			// 	var lnx = nextX + mx * half * miterLength;
			// 	var lny = nextY + my * half * miterLength;
			// 	var rnx = nextX - mx * half * miterLength;
			// 	var rny = nextY - my * half * miterLength;

			// 	if (prevL == -1)
			// 	{
			// 		var lcx = currX + mx * half * miterLength;
			// 		var lcy = currY + my * half * miterLength;
			// 		var rcx = currX - mx * half * miterLength;
			// 		var rcy = currY - my * half * miterLength;
			// 		addVertexPair(lcx, lcy, rcx, rcy);
			// 		firstL = prevL;
			// 		firstR = prevR;
			// 	}

			// 	if (closed && i == segmentCount - 1 && firstL != -1)
			// 	{
			// 		addTriangle(prevL, prevR, firstL);
			// 		addTriangle(prevR, firstR, firstL);
			// 	}
			// 	else
			// 	{
			// 		var prevPrevL = prevL;
			// 		var prevPrevR = prevR;
			// 		addVertexPair(lnx, lny, rnx, rny);
			// 		addTriangle(prevPrevL, prevPrevR, prevL);
			// 		addTriangle(prevPrevR, prevR, prevL);
			// 	}

			// 	continue;
			// }

			var l0x = currX + nxOut * half;
			var l0y = currY + nyOut * half;

			var r0x = currX - nxOut * half;
			var r0y = currY - nyOut * half;

			var l1x = nextX + nxOut * half;
			var l1y = nextY + nyOut * half;

			var r1x = nextX - nxOut * half;
			var r1y = nextY - nyOut * half;

			addSegmentQuad(l0x, l0y, r0x, r0y, l1x, l1y, r1x, r1y);

			if (innerIsLeft)
			{
				nxIn = -nxIn;
				nyIn = -nyIn;
				nxOut = -nxOut;
				nyOut = -nyOut;
			}

			if (i > 0 || closed)
			{
				var c = addVertex(currX, currY);

				switch (joint)
				{
					case BEVEL:
						addVertexPair(currX + nxIn * half, currY + nyIn * half, currX + nxOut * half, currY + nyOut * half);
						addTriangle(c, prevL, prevR);

					case MITER:
						var miterLength = 1 / Math.sqrt((1 + dot) * 0.5);
						if (miterLength > miterLimit)
						{
							addVertexPair(currX + nxIn * half, currY + nyIn * half, currX + nxOut * half, currY + nyOut * half);
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

								var mx = currX + mX * half * miterLength;
								var my = currY + mY * half * miterLength;

								addVertexPair(currX + nxIn * half, currY + nyIn * half, currX + nxOut * half, currY + nyOut * half);
								var m = addVertex(mx, my);

								addTriangle(c, prevL, m);
								addTriangle(c, m, prevR);
							}
						}
					case ROUND:
						var startAng = Math.atan2(nyOut, nxOut);
						var endAng = Math.atan2(nyIn, nxIn);
						var sweep = endAng - startAng;
						if (innerIsLeft)
						{
							if (sweep > 0) sweep -= Math.PI * 2;
						}
						else
						{
							if (sweep < 0) sweep += Math.PI * 2;
						}
						var steps = calculateArcSteps(half, sweep);
						var prevArc = addVertex(currX + Math.cos(startAng) * half, currY + Math.sin(startAng) * half);

						for (k in 1...steps + 1)
						{
							var t = k / steps;
							var ang = startAng + sweep * t;
							var ax = currX + Math.cos(ang) * half;
							var ay = currY + Math.sin(ang) * half;
							var arc = addVertex(ax, ay);
							addTriangle(c, prevArc, arc);
							prevArc = arc;
						}
						if (innerIsLeft)
						{
							prevR = prevArc;
						}
						else
						{
							prevL = prevArc;
						}
				}
			}
		}

		if (!closed && caps != NONE)
		{
			var dxStart = points[2] - points[0];
			var dyStart = points[3] - points[1];
			addCap(caps, points[0], points[1], dxStart, dyStart, half);

			var dxEnd = points[n * 2 - 4] - points[n * 2 - 2];
			var dyEnd = points[n * 2 - 3] - points[n * 2 - 1];
			addCap(caps, points[n * 2 - 2], points[n * 2 - 1], dxEnd, dyEnd, half);
		}
	}

	function addCap(caps:CapsStyle, px:Float, py:Float, dx:Float, dy:Float, half:Float):Void
	{
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len > EPSILON)
		{
			dx /= len;
			dy /= len;
		}
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

	private static function getSignedArea(points:Vector<Float>):Float
	{
		var n = Std.int(points.length / 2);
		if (n < 3) return 0.0;

		var area = 0.0;

		for (i in 0...n)
		{
			var j = (i + 1) % n;

			var x0 = points[i * 2];
			var y0 = points[i * 2 + 1];
			var x1 = points[j * 2];
			var y1 = points[j * 2 + 1];

			area += x0 * y1 - x1 * y0;
		}

		return area * 0.5;
	}

	private static inline function cross(ax:Float, ay:Float, bx:Float, by:Float):Float
	{
		return ax * by - ay * bx;
	}

	private static inline function clamp(x:Float, min:Float, max:Float):Float
	{
		return Math.max(min, Math.min(max, x));
	}

	private static function reversePoints(points:Vector<Float>):Void
	{
		var n = Std.int(points.length / 2);
		var nHalf = Std.int(n / 2);

		for (i in 0...nHalf)
		{
			var j = n - 1 - i;

			var i0 = i * 2;
			var i1 = i * 2 + 1;
			var j0 = j * 2;
			var j1 = j * 2 + 1;

			// swap x
			var tmp = points[i0];
			points[i0] = points[j0];
			points[j0] = tmp;

			// swap y
			tmp = points[i1];
			points[i1] = points[j1];
			points[j1] = tmp;
		}
	}
}
