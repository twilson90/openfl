package openfl.display._internal.geom;

import openfl.display.JointStyle;
import openfl.display.CapsStyle;
import openfl.utils.ArrayUtil;

class PolyLineTesselator
{
	private var prevLeft:Int = -1;
	private var prevRight:Int = -1;
	private var innerIsLeft:Bool = false;
	private var intersectionPoint = {x: 0.0, y: 0.0};
	private var tolerance:Float = 0.25;
	private var numVertices:Int;
	private var innerVertices:Vector<Int> = new Vector<Int>();

	public var vertices:Vector<Float> = new Vector<Float>();
	public var indices:Vector<Int> = new Vector<Int>();

	static private var EPS:Float = 1e-6;

	public function new(tolerance:Float = 0.25)
	{
		this.tolerance = tolerance;
	}

	public function reset()
	{
		vertices.length = 0;
		indices.length = 0;
		innerVertices.length = 0;
		prevLeft = -1;
		prevRight = -1;
		numVertices = 0;
	}

	public function tesselate(points:Array<Float>, closed:Bool, thickness:Float, joint:JointStyle, caps:CapsStyle, miterLimit:Float,
			scaleMode:LineScaleMode):Void
	{
		var len = points.length;
		var half = thickness / 2;
		var n = Std.int(len / 2);

		if (n < 2) return;

		prevLeft = -1;
		prevRight = -1;

		if (n < 3) closed = false;

		for (i in 0...n)
		{
			var prevIdx = (i - 1 + n) % n;
			var currIdx = i;
			var nextIdx = (i + 1) % n;
			var px = points[currIdx * 2];
			var py = points[currIdx * 2 + 1];
			var prevX = points[prevIdx * 2];
			var prevY = points[prevIdx * 2 + 1];
			var nextX = points[nextIdx * 2];
			var nextY = points[nextIdx * 2 + 1];

			// Directions
			var dxIn = px - prevX;
			var dyIn = py - prevY;
			if (Math.abs(dxIn) < EPS && Math.abs(dyIn) < EPS) continue;

			var dxOut = nextX - px;
			var dyOut = nextY - py;
			if (Math.abs(dxOut) < EPS && Math.abs(dyOut) < EPS) continue;

			var lenIn = Math.sqrt(dxIn * dxIn + dyIn * dyIn);
			if (lenIn != 0)
			{
				dxIn /= lenIn;
				dyIn /= lenIn;
			}

			var lenOut = Math.sqrt(dxOut * dxOut + dyOut * dyOut);
			if (lenOut != 0)
			{
				dxOut /= lenOut;
				dyOut /= lenOut;
			}

			// Normals
			var nInX = -dyIn;
			var nInY = dxIn;
			var nOutX = -dyOut;
			var nOutY = dxOut;

			// Offset points for left/right edges
			var leftInX = px + nInX * half;
			var leftInY = py + nInY * half;
			var rightInX = px - nInX * half;
			var rightInY = py - nInY * half;
			var leftOutX = px + nOutX * half;
			var leftOutY = py + nOutY * half;
			var rightOutX = px - nOutX * half;
			var rightOutY = py - nOutY * half;

			var dot = dxIn * dxOut + dyIn * dyOut;
			var det = dxIn * dyOut - dyIn * dxOut;
			var dev = 1 - dot;

			innerIsLeft = det > 0;

			if (!closed)
			{
				if (i == 0)
				{
					addVertexPair(leftOutX, leftOutY, rightOutX, rightOutY);
					addCap(caps, half, px, py, dxOut, dyOut, nOutX, nOutY, true);
					continue;
				}
				else if (i == n - 1)
				{
					addVertexPair(leftInX, leftInY, rightInX, rightInY);
					addCap(caps, half, px, py, dxIn, dyIn, nInX, nInY, false);
					continue;
				}
			}

			// determine inner/outer sides
			var innerInX:Float;
			var innerInY:Float;
			var innerOutX:Float;
			var innerOutY:Float;
			var outerInX:Float;
			var outerInY:Float;
			var outerOutX:Float;
			var outerOutY:Float;

			if (innerIsLeft)
			{
				innerInX = leftInX;
				innerInY = leftInY;
				innerOutX = leftOutX;
				innerOutY = leftOutY;
				outerInX = rightInX;
				outerInY = rightInY;
				outerOutX = rightOutX;
				outerOutY = rightOutY;
			}
			else
			{
				innerInX = rightInX;
				innerInY = rightInY;
				innerOutX = rightOutX;
				innerOutY = rightOutY;
				outerInX = leftInX;
				outerInY = leftInY;
				outerOutX = leftOutX;
				outerOutY = leftOutY;
			}

			var tInner = ((innerOutX - innerInX) * dyOut - (innerOutY - innerInY) * dxOut) / det;
			var innerX = innerInX + tInner * dxIn;
			var innerY = innerInY + tInner * dyIn;

			var currJoint = joint;
			if (currJoint == MITER)
			{
				var angle = Math.acos(dot);
				if (angle > miterLimit || Math.abs(det) < 1e-6)
				{
					currJoint = BEVEL;
				}
			}

			switch (currJoint)
			{
				case MITER:
					var tOuter = ((outerOutX - outerInX) * dyOut - (outerOutY - outerInY) * dxOut) / det;
					var outerX = outerInX + tOuter * dxIn;
					var outerY = outerInY + tOuter * dyIn;
					if (innerIsLeft)
					{
						addVertexPair(innerX, innerY, outerX, outerY);
					}
					else
					{
						addVertexPair(outerX, outerY, innerX, innerY);
					}
				case BEVEL:
					if (innerIsLeft)
					{
						addVertexPair(innerX, innerY, outerInX, outerInY);
						addVertexPair(innerX, innerY, outerOutX, outerOutY);
					}
					else
					{
						addVertexPair(outerInX, outerInY, innerX, innerY);
						addVertexPair(outerOutX, outerOutY, innerX, innerY);
					}
				case ROUND:
					if (innerIsLeft)
					{
						addVertexPair(innerX, innerY, outerInX, outerInY);
						addArcJoin(half, px, py, innerX, innerY, outerInX, outerInY, outerOutX, outerOutY);
					}
					else
					{
						addVertexPair(outerInX, outerInY, innerX, innerY);
						addArcJoin(half, px, py, innerX, innerY, outerOutX, outerOutY, outerInX, outerInY);
					}
			}
		}

		collapseInnerLoops();

		if (closed)
		{
			addTriangle(prevRight, 0, prevLeft);
			addTriangle(1, 0, prevRight);
		}
	}

	private function collapseInnerLoops():Void
	{
		var n = innerVertices.length;
		if (n < 3) return;

		var i = 0;
		while (i < n)
		{
			var idxA0 = innerVertices[i];
			var idxA1 = innerVertices[(i + 1) % n];

			var ax0 = vertices[idxA0 * 2];
			var ay0 = vertices[idxA0 * 2 + 1];
			var ax1 = vertices[idxA1 * 2];
			var ay1 = vertices[idxA1 * 2 + 1];

			var foundIntersection = false;

			for (j in i + 2...n + i - 1)
			{
				var jj0 = j % n;
				var jj1 = (j + 1) % n;

				var idxB0 = innerVertices[jj0];
				var idxB1 = innerVertices[jj1];

				var bx0 = vertices[idxB0 * 2];
				var by0 = vertices[idxB0 * 2 + 1];
				var bx1 = vertices[idxB1 * 2];
				var by1 = vertices[idxB1 * 2 + 1];

				if (intersect(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1, intersectionPoint))
				{
					// Collapse all vertices between idxA1 and idxB0 (inclusive) to the intersection
					var k = (i + 1) % n;
					while (k != jj0)
					{
						vertices[innerVertices[k] * 2] = intersectionPoint.x;
						vertices[innerVertices[k] * 2 + 1] = intersectionPoint.y;
						k = (k + 1) % n;
					}

					// Also collapse idxB0 itself
					vertices[innerVertices[jj0] * 2] = intersectionPoint.x;
					vertices[innerVertices[jj0] * 2 + 1] = intersectionPoint.y;

					// Move i to the last collapsed vertex to continue
					i = jj0;
					foundIntersection = true;
					break;
				}
			}

			if (!foundIntersection) i++;
		}
	}

	private function addVertexPair(leftX:Float, leftY:Float, rightX:Float, rightY:Float):Void
	{
		var prevPrevLeft = prevLeft;
		var prevPrevRight = prevRight;

		addLeftVertex(leftX, leftY);
		addRightVertex(rightX, rightY);

		if (innerIsLeft)
		{
			if (prevLeft != prevPrevLeft) innerVertices.push(prevLeft);
		}
		else
		{
			if (prevRight != prevPrevRight) innerVertices.push(prevRight);
		}

		if (prevPrevLeft >= 0 && prevPrevRight >= 0)
		{
			if (prevLeft != prevPrevLeft) addTriangle(prevPrevRight, prevLeft, prevPrevLeft);
			if (prevRight != prevPrevRight) addTriangle(prevRight, prevLeft, prevPrevRight);
		}
	}

	private inline function addVertex(x:Float, y:Float):Int
	{
		vertices.push(x);
		vertices.push(y);
		numVertices++;
		return numVertices - 1;
	}

	private inline function addLeftVertex(x:Float, y:Float):Int
	{
		var prevX = vertices[prevLeft * 2];
		var prevY = vertices[prevLeft * 2 + 1];
		if (x != prevX || y != prevY)
		{
			prevLeft = addVertex(x, y);
		}
		return prevLeft;
	}

	private inline function addRightVertex(x:Float, y:Float):Int
	{
		var prevX = vertices[prevRight * 2];
		var prevY = vertices[prevRight * 2 + 1];
		if (x != prevX || y != prevY)
		{
			prevRight = addVertex(x, y);
		}
		return prevRight;
	}

	private inline function addTriangle(i0:Int, i1:Int, i2:Int):Void
	{
		indices.push(i0);
		indices.push(i1);
		indices.push(i2);
	}

	private function addCap(caps:CapsStyle, half:Float, px:Float, py:Float, dirX:Float, dirY:Float, nx:Float, ny:Float, isStart:Bool):Void
	{
		switch (caps)
		{
			case NONE:
				return;
			case SQUARE:
				var backX = px + dirX;
				var backY = py + dirY;
				addVertexPair(backX + nx * half, backY + ny * half, backX - nx * half, backY - ny * half);
			case ROUND:
				var startAng = Math.atan2(ny, nx);
				var sweep = isStart ? Math.PI : -Math.PI;
				var steps = calculateArcSteps(half, sweep);
				var baseL = px + nx * half;
				var baseR = px - nx * half;
				var prevIdx = prevLeft;
				for (k in 1...steps + 1)
				{
					var t = k / steps;
					var ang = startAng + t * sweep;
					var x = px + half * Math.cos(ang);
					var y = py + half * Math.sin(ang);
					var currIdx = addVertex(x, y);
					if (isStart)
					{
						addTriangle(prevRight, prevIdx, currIdx);
					}
					else
					{
						addTriangle(prevRight, currIdx, prevIdx);
					}
					prevIdx = currIdx;
				}
		}
	}

	private function addArcJoin(half:Float, cx:Float, cy:Float, ax:Float, ay:Float, x0:Float, y0:Float, x1:Float, y1:Float)
	{
		var startAng = Math.atan2(y0 - cy, x0 - cx);
		var endAng = Math.atan2(y1 - cy, x1 - cx);
		var delta = (endAng - startAng + Math.PI) % (2 * Math.PI) - Math.PI;

		var steps = calculateArcSteps(half, delta);

		var outerIdx = innerIsLeft ? prevLeft : prevRight;
		var prevIdx = innerIsLeft ? prevRight : prevLeft;

		for (k in 0...steps + 1)
		{
			var t = k / steps;
			var ang = startAng + t * delta;
			var px = cx + half * Math.cos(ang);
			var py = cy + half * Math.sin(ang);
			addVertexPair(ax, ay, px, py);
		}
	}

	private inline function calculateArcSteps(half:Float, angle:Float)
	{
		var maxStep = 2 * Math.acos(Math.max(0, 1 - tolerance / half));
		var steps = Math.ceil(Math.abs(angle) / maxStep);
		if (steps < 1) return 1;
		return steps;
	}

	static private function intersect(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, dx:Float, dy:Float, result:{x:Float, y:Float}):Bool
	{
		var abx = bx - ax;
		var aby = by - ay;
		var cdx = dx - cx;
		var cdy = dy - cy;

		var det = abx * cdy - aby * cdx;
		if (Math.abs(det) < EPS) return false;

		var t = ((cx - ax) * cdy - (cy - ay) * cdx) / det;
		var u = ((cx - ax) * aby - (cy - ay) * abx) / det;

		if (t > 0 && t < 1 && u > 0 && u < 1)
		{
			result.x = ax + t * abx;
			result.y = ay + t * aby;
			return true;
		}

		return false;
	}
}
