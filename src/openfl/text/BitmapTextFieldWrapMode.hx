package openfl.text;

/**
 * Possible BitmapTextField align modes.
 */
#if (haxe_ver >= 4.0) enum #else @:enum #end abstract BitmapTextFieldWrapMode(String) from String
{
	var CHAR = "char";
	var WORD = "word";
	var NONE = "none";
}
