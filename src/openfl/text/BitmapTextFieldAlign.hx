package openfl.text;

/**
 * Possible BitmapTextField align modes.
 */
#if (haxe_ver >= 4.0) enum #else @:enum #end abstract BitmapTextFieldAlign(String) from String
{
	var LEFT = "left";
	var CENTER = "center";
	var RIGHT = "right";
	var TOP = "top";
	var MIDDLE = "middle";
	var BOTTOM = "bottom";
}
