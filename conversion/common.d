/**
 * Provides common functions during language conversion.
 */
module ProtocolBuffer.conversion.common;

version(D_Version2) {
	import std.algorithm;
	import std.conv;
	import std.range;
	import std.regex;
} else {
	import std.string;
}

/*
 * Converts a numeric to an intent string
 */
string indented(int indentCount) {
	version(D_Version2)
		return to!string(repeat("\t", indentCount).join.array);
	else
		return repeat("\t", indentCount);
}
