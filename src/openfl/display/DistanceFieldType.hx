package openfl.display;

#if (haxe_ver >= 4.0) enum #else @:enum #end abstract DistanceFieldType(String) from String
{
	var MSDF = "msdf";
	var SDF = "sdf";
	var PSDF = "psdf";
	var NONE = "none";
}
