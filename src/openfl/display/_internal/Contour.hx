package openfl.display._internal;

import openfl.utils.ObjectPool;
import openfl.utils._internal.FastHash;
import openfl.geom.Rectangle;

class Contour
{
	public var segments:Vector<Segment> = new Vector<Segment>();
	public var curveTolerance(get, set):Float;
	public var points(get, never):Vector<Float>;
	public var curves(get, never):Vector<Bool>;
	public var length(get, never):Float;
	public var bounds(get, never):Rectangle;
	public var hash(get, never):FastHash;
	public var closed(get, never):Bool;

	private var __curveTolerance:Float = 0.25;
	private var __points:Vector<Float> = new Vector<Float>();
	private var __curves:Vector<Bool> = new Vector<Bool>();
	private var __pointsDirty:Bool = false;
	private var __lengthDirty:Bool = false;
	private var __boundsDirty:Bool = false;
	private var __hashDirty:Bool = false;
	private var __startX:Float = 0;
	private var __startY:Float = 0;
	private var __currentX:Float = 0.0;
	private var __currentY:Float = 0.0;
	private var __length:Float = 0.0;
	private var __bounds:Rectangle = null;
	private var __hash:FastHash;

	private static var __pool:ObjectPool<Contour> = new ObjectPool<Contour>(() -> new Contour(), (c) -> c.init(0, 0));
	private static var __tempExtrema:Vector<Float> = new Vector<Float>();

	private function get_points()
	{
		evaluatePoints();
		return __points;
	}

	private function get_curves()
	{
		evaluatePoints();
		return __curves;
	}

	private function get_length():Float
	{
		evaluateLength();
		return __length;
	}

	private function get_bounds():Rectangle
	{
		evaluateBounds();
		return __bounds;
	}

	private function get_curveTolerance():Float
	{
		return __curveTolerance;
	}

	private function set_curveTolerance(value:Float):Float
	{
		__curveTolerance = value;
		__pointsDirty = true;
		return value;
	}

	private function get_hash():FastHash
	{
		if (__hashDirty)
		{
			__hashDirty = false;
			__hash = new FastHash();
			__hash += __startX;
			__hash += __startY;
			for (seg in segments)
			{
				switch (seg)
				{
					case LINE_TO(ax, ay):
						__hash += 0;
						__hash += ax;
						__hash += ay;
					case CURVE_TO(cx, cy, ax, ay):
						__hash += 1;
						__hash += cx;
						__hash += cy;
						__hash += ax;
						__hash += ay;
					case CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, ax, ay):
						__hash += 2;
						__hash += cx1;
						__hash += cy1;
						__hash += cx2;
						__hash += cy2;
						__hash += ax;
						__hash += ay;
				}
			}
		}
		return __hash;
	}

	private function get_closed():Bool
	{
		return __startX == __currentX && __startY == __currentY;
	}

	public function new()
	{
		init(0, 0);
	}

	public inline function init(x:Float, y:Float)
	{
		curveTolerance = 0.25;
		segments.length = 0;
		__startX = x;
		__startY = y;
		__currentX = x;
		__currentY = y;
		__setDirty();
	}

	public function close()
	{
		if (!closed)
		{
			append(LINE_TO(__startX, __startY));
		}
	}

	private function __setDirty()
	{
		__hashDirty = true;
		__pointsDirty = true;
		__lengthDirty = true;
		__boundsDirty = true;
	}

	private function evaluateLength()
	{
		if (!__lengthDirty) return;
		__length = 0;
		for (seg in segments)
		{
			var x:Float;
			var y:Float;
			switch (seg)
			{
				case LINE_TO(ax, ay):
					x = ax;
					y = ay;
				case CURVE_TO(cx, cy, ax, ay):
					x = ax;
					y = ay;
				case CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, ax, ay):
					x = ax;
					y = ay;
			}
			__length += segmentLength(x, y, seg);
		}
		__lengthDirty = false;
	}

	private function evaluateBounds()
	{
		if (!__boundsDirty) return;
		if (__bounds == null) __bounds = new Rectangle();
		__bounds.setTo(Math.NaN, Math.NaN, Math.NaN, Math.NaN);
		for (seg in segments)
		{
			segmentBounds(__currentX, __currentY, seg, __bounds);
		}
		__boundsDirty = false;
	}

	private function evaluatePoints()
	{
		if (!__pointsDirty) return;
		__points.length = 0;
		__curves.length = 0;
		__points.push(__startX);
		__points.push(__startY);
		__curves.push(false);
		var n1 = 1;
		for (seg in segments)
		{
			segmentPoints(seg, __curveTolerance, __points);
			var n2 = Std.int(__points.length / 2);
			for (i in n1...(n2 - 1))
			{
				__curves.push(true);
			}
			__curves.push(false);
			n1 = n2;
		}
		// if (closed && __points[__points.length - 2] == __startX && __points[__points.length - 1] == __startY)
		// {
		// 	__points.length -= 2;
		// 	__curves.length -= 1;
		// }
		__pointsDirty = false;
	}

	public function append(seg:Segment)
	{
		switch (seg)
		{
			case LINE_TO(ax, ay):
				if (__currentX == ax && __currentY == ay) return;
				__currentX = ax;
				__currentY = ay;
			case CURVE_TO(cx, cy, ax, ay):
				__currentX = ax;
				__currentY = ay;
			case CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, ax, ay):
				__currentX = ax;
				__currentY = ay;
		}
		segments.push(seg);
		__setDirty();
	}

	public inline function end()
	{
		// don't set closed if already set to true
		// if (segments.length >= 2 && !closed)
		// {
		// 	closed = __startX == __currentX && __startY == __currentY;
		// }
	}

	public static function segmentPoints(segment:Segment, curveTolerance:Float, points:Vector<Float>)
	{
		var x = points[points.length - 2];
		var y = points[points.length - 1];
		switch (segment)
		{
			case LINE_TO(ax, ay):
				points.push(ax);
				points.push(ay);
			case CURVE_TO(cx, cy, ax, ay):
				__subdivideQuadratic(x, y, cx, cy, ax, ay, curveTolerance, points);
			case CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, ax, ay):
				__subdivideCubic(x, y, cx1, cy1, cx2, cy2, ax, ay, curveTolerance, points);
		}
	}

	public static function segmentBounds(x0:Float, y0:Float, segment:Segment, result:Rectangle)
	{
		switch (segment)
		{
			case LINE_TO(ax, ay):
				__expand(result, ax, ay);
			case CURVE_TO(cx, cy, ax, ay):
				__expand(result, ax, ay);
				var tx = __quadExtreme(x0, cx, ax);
				if (tx >= 0)
				{
					var x = __quadAt(x0, cx, ax, tx);
					var y = __quadAt(y0, cy, ay, tx);
					__expand(result, x, y);
				}
				var ty = __quadExtreme(y0, cy, ay);
				if (ty >= 0)
				{
					var x = __quadAt(x0, cx, ax, ty);
					var y = __quadAt(y0, cy, ay, ty);
					__expand(result, x, y);
				}
			case CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, ax, ay):
				__expand(result, ax, ay);
				var txs = __cubicExtrema(x0, cx1, cx2, ax, __tempExtrema);
				for (tx in txs)
				{
					var x = __cubicAt(x0, cx1, cx2, ax, tx);
					var y = __cubicAt(y0, cy1, cy2, ay, tx);
					__expand(result, x, y);
				}
				var tys = __cubicExtrema(y0, cy1, cy2, ay, __tempExtrema);
				for (ty in tys)
				{
					var x = __cubicAt(x0, cx1, cx2, ax, ty);
					var y = __cubicAt(y0, cy1, cy2, ay, ty);
					__expand(result, x, y);
				}
		}
	}

	public static function segmentLength(x0:Float, y0:Float, segment:Segment, ?iterations:Int = 6):Float
	{
		switch (segment)
		{
			case LINE_TO(ax, ay):
				return __hypot(ax - x0, ay - y0);
			case CURVE_TO(cx, cy, ax, ay):
				return __recursiveLen(x0, y0, cx, cy, ax, ay, iterations);
			case CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, ax, ay):
				return __recursiveLenCubic(x0, y0, cx1, cy1, cx2, cy2, ax, ay, iterations);
		}
	}

	private static function __subdivideQuadratic(sx:Float, sy:Float, cx:Float, cy:Float, ax:Float, ay:Float, curveTolerance:Float, points:Vector<Float>)
	{
		var dx = ax - sx;
		var dy = ay - sy;

		var d = Math.abs((cx - ax) * dy - (cy - ay) * dx);

		if (d * d <= curveTolerance * (dx * dx + dy * dy))
		{
			points.push(ax);
			points.push(ay);
			return;
		}

		var x01 = (sx + cx) * 0.5;
		var y01 = (sy + cy) * 0.5;

		var x12 = (cx + ax) * 0.5;
		var y12 = (cy + ay) * 0.5;

		var xm = (x01 + x12) * 0.5;
		var ym = (y01 + y12) * 0.5;

		__subdivideQuadratic(sx, sy, x01, y01, xm, ym, curveTolerance, points);
		__subdivideQuadratic(xm, ym, x12, y12, ax, ay, curveTolerance, points);
	}

	private static function __subdivideCubic(sx:Float, sy:Float, cx1:Float, cy1:Float, cx2:Float, cy2:Float, ax:Float, ay:Float, curveTolerance:Float,
			points:Vector<Float>)
	{
		var dx = ax - sx;
		var dy = ay - sy;

		var d1 = Math.abs((cx1 - ax) * dy - (cy1 - ay) * dx);
		var d2 = Math.abs((cx2 - ax) * dy - (cy2 - ay) * dx);

		if ((d1 + d2) * (d1 + d2) <= curveTolerance * (dx * dx + dy * dy))
		{
			points.push(ax);
			points.push(ay);
			return;
		}

		var x01 = (sx + cx1) * 0.5;
		var y01 = (sy + cy1) * 0.5;

		var x12 = (cx1 + cx2) * 0.5;
		var y12 = (cy1 + cy2) * 0.5;

		var x23 = (cx2 + ax) * 0.5;
		var y23 = (cy2 + ay) * 0.5;

		var x012 = (x01 + x12) * 0.5;
		var y012 = (y01 + y12) * 0.5;

		var x123 = (x12 + x23) * 0.5;
		var y123 = (y12 + y23) * 0.5;

		var xm = (x012 + x123) * 0.5;
		var ym = (y012 + y123) * 0.5;

		__subdivideCubic(sx, sy, x01, y01, x012, y012, xm, ym, curveTolerance, points);
		__subdivideCubic(xm, ym, x123, y123, x23, y23, ax, ay, curveTolerance, points);
	}

	static function __quadExtreme(p0:Float, p1:Float, p2:Float):Float
	{
		var denom = p0 - 2 * p1 + p2;
		if (denom == 0) return -1; // no internal extremum

		var t = (p0 - p1) / denom;
		if (t > 0 && t < 1) return t;
		return -1;
	}

	static function __quadAt(p0:Float, p1:Float, p2:Float, t:Float):Float
	{
		var u = 1 - t;
		return u * u * p0 + 2 * u * t * p1 + t * t * p2;
	}

	static function __hypot(x:Float, y:Float):Float
	{
		return Math.sqrt(x * x + y * y);
	}

	static function __expand(rect:Rectangle, x:Float, y:Float)
	{
		if (Math.isNaN(rect.x))
		{
			rect.setTo(x, y, 0, 0);
			return;
		}
		var minX = rect.x;
		var minY = rect.y;
		var maxX = rect.x + rect.width;
		var maxY = rect.y + rect.height;
		if (x < minX) minX = x;
		if (y < minY) minY = y;
		if (x > maxX) maxX = x;
		if (y > maxY) maxY = y;
		rect.setTo(minX, minY, maxX - minX, maxY - minY);
	}

	static function __cubicAt(p0:Float, p1:Float, p2:Float, p3:Float, t:Float):Float
	{
		var u = 1 - t;
		return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3;
	}

	static function __cubicExtrema(p0:Float, p1:Float, p2:Float, p3:Float, result:Vector<Float>):Vector<Float>
	{
		result.length = 0;

		var a = -p0 + 3 * p1 - 3 * p2 + p3;
		var b = 2 * (p0 - 2 * p1 + p2);
		var c = p1 - p0;

		if (Math.abs(a) < 1e-12)
		{
			if (Math.abs(b) >= 1e-12)
			{
				var t = -c / b;
				if (t > 0 && t < 1) result.push(t);
			}
		}
		else
		{
			var disc = b * b - 4 * a * c;
			if (disc >= 0)
			{
				var s = Math.sqrt(disc);
				var inv = 1 / (2 * a);

				var t0 = (-b - s) * inv;
				if (t0 > 0 && t0 < 1) result.push(t0);

				var t1 = (-b + s) * inv;
				if (t1 > 0 && t1 < 1) result.push(t1);
			}
		}

		return result;
	}

	static function __recursiveLen(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, depth:Int):Float
	{
		// straight-line approximation
		var dx = x2 - x0;
		var dy = y2 - y0;
		var chord = __hypot(dx, dy);

		// control polygon length
		var cont = __hypot(x1 - x0, y1 - y0) + __hypot(x2 - x1, y2 - y1);

		// flat enough?
		if (depth <= 0 || Math.abs(cont - chord) < 0.01)
		{
			return 0.5 * (cont + chord);
		}

		// subdivide curve
		var x01 = (x0 + x1) * 0.5;
		var y01 = (y0 + y1) * 0.5;
		var x12 = (x1 + x2) * 0.5;
		var y12 = (y1 + y2) * 0.5;

		var x012 = (x01 + x12) * 0.5;
		var y012 = (y01 + y12) * 0.5;

		return __recursiveLen(x0, y0, x01, y01, x012, y012, depth - 1) + __recursiveLen(x012, y012, x12, y12, x2, y2, depth - 1);
	}

	static function __recursiveLenCubic(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, depth:Int):Float
	{
		// chord
		var dx = x3 - x0;
		var dy = y3 - y0;
		var chord = __hypot(dx, dy);

		// control polygon
		var cont = __hypot(x1 - x0, y1 - y0) + __hypot(x2 - x1, y2 - y1) + __hypot(x3 - x2, y3 - y2);

		// flat enough
		if (depth <= 0 || Math.abs(cont - chord) < 0.01)
		{
			return 0.5 * (cont + chord);
		}

		// de Casteljau split
		var x01 = (x0 + x1) * 0.5;
		var y01 = (y0 + y1) * 0.5;

		var x12 = (x1 + x2) * 0.5;
		var y12 = (y1 + y2) * 0.5;

		var x23 = (x2 + x3) * 0.5;
		var y23 = (y2 + y3) * 0.5;

		var x012 = (x01 + x12) * 0.5;
		var y012 = (y01 + y12) * 0.5;

		var x123 = (x12 + x23) * 0.5;
		var y123 = (y12 + y23) * 0.5;

		var x0123 = (x012 + x123) * 0.5;
		var y0123 = (y012 + y123) * 0.5;

		// recurse left + right
		return __recursiveLenCubic(x0, y0, x01, y01, x012, y012, x0123, y0123, depth - 1)
			+ __recursiveLenCubic(x0123, y0123, x123, y123, x23, y23, x3, y3, depth - 1);
	}
}

enum Segment
{
	LINE_TO(x:Float, y:Float);
	CURVE_TO(cx:Float, cy:Float, ax:Float, ay:Float);
	CUBIC_CURVE_TO(cx1:Float, cy1:Float, cx2:Float, cy2:Float, ax:Float, ay:Float);
}
