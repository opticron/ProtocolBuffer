/**
 * This module provides the functions needed to convert to/from
 * the Protocol Buffer binary format.
 */
module ProtocolBuffer.conversion.pbbinary;

version(D_Version2) {
	import std.conv;
} else
	import ProtocolBuffer.d1support;

import std.stdio;

/**
 * Stores the integer value for each wire type.
 *
 * Undecided is used on custom types; given a type name
 * a wire type can not be determined until identifying
 * if the type is a enum or struct.
 */
enum WireType : byte {
	varint,
	fixed64,
	lenDelimited,
	startGroup, // Deprecated
	endGroup, // Deprecated
	fixed32,
	undecided = -1
}

/**
 * Encode a type as a varint.
 */
ubyte[]toVarint(bool input,int field) {
	return toVarint(cast(long)(input?1:0),field);
}
/// ditto
ubyte[]toVarint(uint input,int field) {
	return toVarint(cast(long)input,field);
}
/// ditto
ubyte[]toVarint(int input,int field) {
	return toVarint(cast(long)input,field);
}
/// ditto
ubyte[]toVarint(ulong input,int field) {
	return toVarint(cast(long)input,field);
}
/// ditto
ubyte[]toVarint(long input,int field) {
	ubyte[]ret;
	// tack on the header and the varint
	ret = genHeader(field,WireType.varint)~toVarint(input);
	return ret;
}

/**
 * Encode a varint without a header.
 */
ubyte[] toVarint(long input) {
	ubyte[]ret;
	int x;
	if (input < 0) {
		// shortcut negative numbers, this is always the case
		ret.length = 10;
	} else {
		long tmp = input;
		for (x = 1;tmp >= 128;x++) {
			// arithmetic shift is fine, because we've already checked for
			// negative numbers
			tmp >>= 7;
		}
		ret.length = x;
	}
	for (x = 0;x<ret.length;x++) {
		// set the top bit
		ret[x] = cast(ubyte)(1<<7);
		ret[x] |= (cast(ubyte)input)&0b1111111;
		input >>= 7;
	}
	// unset the top bit of the last data element
	ret[$-1] &= 0b1111111;
	return ret;
}

/**
 * Decodes a varint to the requested type.
 */
T fromVarint(T)(ref ubyte[] input)
in {
	assert(input.length);
} body {
	// find last ubyte
	int x;
	ubyte[]tmp;
	for (x = 0;x<=input.length;x++) {
		if (x == input.length) throw new Exception(
			"Found no end to varint ubyte string starting with: "~
			to!(string)(cast(ulong)input[0],16u)~" "~
			(input.length>1?to!(string)(cast(ulong)input[1],16u):"")~" "~
			(input.length>2?to!(string)(cast(ulong)input[2],16u):""));

		if (!(input[x]>>7)) {
			// we have a ubyte with an unset upper bit! huzzah!
			// this means we have the whole varint ubyte string
			tmp = input[0..x+1];
			input = input[x+1..$];
			break;
		}
	}

	long output = 0;
	version(D_Version2)
		auto starting = to!(int)(tmp.length-1);
	else
		auto starting = tmp.length-1;
	for (x = starting;x>=0;x--) {
		output |= (tmp[x]&0b1111111);
		if (x==0) {
			// we're done, so jump out so we can return values
			break;
		}
		output <<= 7;
	}
	if (output > T.max || output < T.min) {
		throw new Exception("Integer parse is not within the valid range.");
	}
	return cast(T)output;
}

/**
 * Provide the specified wiretype from the header.
 *
 * Does not varify type is known as future wire types
 * could be introduced.
 */
WireType getWireType(int header) {
	return cast(WireType)(header&0b111);
}

/**
 * Provide the specified field number from the header.
 */
int getFieldNumber(int header) {
	return header>>3;
}

/**
 * Encodes a header.
 */
ubyte[] genHeader(int field, WireType wiretype) {
	return toVarint((field<<3)|wiretype);
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.toVarint");
	debug writefln("toVarint(bool)...");
	ubyte[]tmp = toVarint(true,5);
	ubyte cmp;
	debug writefln("length");
	assert(tmp.length == 2);
	debug writefln("header");
	assert(getFieldNumber(tmp[0]) == 5);
	cmp = cast(ubyte)0b00000001;
	debug writefln("first data ubyte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	debug writefln("toVarint(int)...");
	tmp = toVarint(300,12);
	debug writefln("length");
	assert(tmp.length == 3);
	cmp = cast(ubyte)0b10101100;
	debug writefln("first data ubyte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	cmp = cast(ubyte)0b00000010;
	debug writefln("second data ubyte(%b): %b",cmp,tmp[2]);
	assert(tmp[2] == cmp);
	debug writefln("long fromVarint...");
	// use last value with the header ripped off
	cmp = tmp[0];
	tmp = tmp[1..$];
	long ret = fromVarint!(long)(tmp);
	assert(ret == 300);

	debug writefln("Checking max/min edges...");
	tmp = toVarint(ulong.max,5);
	tmp = tmp[1..$];
	assert(ulong.max == fromVarint!(ulong)(tmp));

	tmp = toVarint(long.min,5);
	tmp = tmp[1..$];
	assert(long.min == fromVarint!(long)(tmp));

	tmp = toVarint(int.min,5);
	tmp = tmp[1..$];
	assert(int.min == fromVarint!(int)(tmp));

	tmp = toVarint(uint.max,5);
	tmp = tmp[1..$];
	uint uitmp = fromVarint!(uint)(tmp);
	debug writefln("%d should be %d",uitmp,uint.max);
	assert(uint.max == uitmp);
	assert(tmp.length == 0);
	debug writefln("");
}

// zigzag encoding and decodings
ubyte[]toSInt(int input,int field) {
	return toVarint((input<<1)^(input>>31),field);
}
ubyte[]toSInt(long input,int field) {
	return toVarint((input<<1)^(input>>63),field);
}

T fromSInt(T)(ref ubyte[]input) {
	static assert(is(T == int) || is(T == long),
		"fromSInt only works with types int or long.");

	T tmp = fromVarint!(T)(input);
	tmp = (tmp>>1)^cast(T)(tmp&0x1?0xFFFFFFFFFFFFFFFF:0);
	return tmp;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.toSInt");
	debug writefln("toSInt(int)...");
	ubyte[]tmp = toSInt(0,12);
	debug writefln("length");
	assert(tmp.length == 2);
	ubyte cmp = cast(ubyte)0b0;
	debug writefln("first ubyte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	cmp = cast(ubyte)(12<<3);
	debug writefln("header ubyte(%b): %b",cmp,tmp[0]);
	assert(tmp[0] == cmp);

	debug writefln("toSInt(long)...");
	tmp = toSInt(cast(long)-2,12);
	debug writefln("length");
	assert(tmp.length == 2);
	cmp = cast(ubyte)0b11;
	debug writefln("first ubyte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);

	debug writefln("fromSInt(long)...");
	// slice off header for reuse
	tmp = tmp[1..$];
	assert(-2 == fromSInt!(long)(tmp));
	assert(tmp.length == 0);
	debug writefln("");
}

/**
 * Fixed sized numeric types.
 *
 * Valid for uint, float, ulong, and double
 */
ubyte[]toByteBlob(T)(T input,int field) {
	ubyte[]ret;
	ubyte[]tmp = (cast(ubyte*)&input)[0..T.sizeof].dup;
	version (BigEndian) {tmp.reverse;}
	ret = genHeader(field,T.sizeof==8?WireType.fixed64:WireType.fixed32)
	      ~tmp[0..T.sizeof];
	return ret;
}

/// ditto
T fromByteBlob(T)(ref ubyte[]input)
in {
	assert(input.length >= T.sizeof);
} body {
	T ret;
	ubyte[]tmp = input[0..T.sizeof];
	input = input[T.sizeof..$];
	version (BigEndian) {tmp.reverse;}
	(cast(ubyte*)&ret)[0..T.sizeof] = tmp[0..T.sizeof];
	return ret;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.byteblobs");
	ubyte[]tmp = toByteBlob!(double)(1.542,cast(ubyte)5)[1..$];
	assert(1.542 == fromByteBlob!(double)(tmp));
	assert(tmp.length == 0);
	debug writefln("");
}

/**
 * Handle strings
 */
ubyte[]toByteString(T)(T[]input,int field) {
	// we need to rip off the generated header ubyte for code reuse, this could
	// be done better
	ubyte[]tmp = toVarint(input.length);
	return genHeader(field,WireType.lenDelimited)~tmp~cast(ubyte[])input;
}

/// ditto
T[]fromByteString(T:T[])(ref ubyte[]input) {
	uint len = fromVarint!(uint)(input);
	if (len > input.length) {
		throw new Exception("String length exceeds length of input ubyte array.");
	}
	T[]ret = cast(T[])input[0..len];
	input = input[len..$];
	return ret;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.byteblobs");
	string test = "My toast has been stolen!";
	ubyte[]tmp = toByteString(test,cast(ubyte)15)[1..$];
	assert(test == fromByteString!(string)(tmp));
	assert(tmp.length == 0);
	debug writefln("");

	ubyte[] data = [0x03, // Length
	    0x05, 0x06, 0x07,
	    0x00, // Length
	    0x01, // Length
	    0x08];
	assert(fromByteString!(ubyte[])(data) == cast(ubyte[])[0x05, 0x06, 0x07]);
	assert(fromByteString!(ubyte[])(data) == cast(ubyte[])[]);
	assert(fromByteString!(ubyte[])(data) == cast(ubyte[])[0x08]);
}

/**
 * Remove unknown field from input.
 *
 * Returns:
 * The data of field.
 */
ubyte[]ripUField(ref ubyte[]input,int wiretype) {
	switch(wiretype) {
	case 0:
		// snag a varint
		return toVarint(fromVarint!(long)(input));
	case 1:
		// snag a 64bit chunk
		ubyte[]tmp = input[0..8];
		input = input[8..$];
		return tmp;
	case 2:
		// snag a length delimited chunk
		auto blen = fromVarint!(long)(input);
		ubyte[]tmp = input[0..cast(uint)blen];
		return toVarint(blen)~tmp;
	case 5:
		// snag a 32bit chunk
		ubyte[]tmp = input[0..4];
		input = input[4..$];
		return tmp;
	default:
		// shit is broken....
		throw new Exception("Can't deal with wiretype "~to!(string)(wiretype));
	}
	assert(0);
}

/**
 * Handle packed fields.
 */
ubyte[]toPacked(T:T[],alias serializer)(T[] packed,int field) {
	// zero length packed repeated fields serialize to nothing
	if (!packed.length) return null;
	ubyte[]ret;
	foreach(pack;packed) {
		// serialize everything, but leave off the header bytes for all of them
		ret ~= serializer(pack,field)[1..$];
	}
	// now that everything is serialized, grab the length, convert to varint,
	// and tack on a header
	ret = genHeader(field,WireType.lenDelimited)~toVarint(ret.length)~ret;
	return ret;
}

/// ditto
T[]fromPacked(T,alias deserializer)(ref ubyte[]input) {
	T[]ret;
	// it's assumed that the field is already ripped off
	// grab the length to be decoded
	auto len = fromVarint!(uint)(input);
	if (input.length < len) throw new Exception("A repeated packed field specifies a length longer than available data.");
	// rip off the chunk that's ours and process the hell out of it
	ubyte[]own = input[0..len];
	input = input[len..$];
	while(own.length) {
		ret ~= cast(T) deserializer(own);
	}
	return ret;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.packed_fields");
	int[]test = [3,270,86942];
	ubyte[]cmp = cast(ubyte[])[0x22,0x6,0x3,0x8e,0x2,0x9e,0xa7,0x5];
	ubyte[]tmp = toPacked!(int[],toVarint)(test,cast(ubyte)4);
	assert(tmp.length == 8);
	version(D_Version2) {
		mixin("import std.algorithm, std.range;");
		debug writeln(map!((a) { return format("%x", a); })(cmp));
		debug writeln(map!((a) { return format("%x", a); })(tmp));
	} else {
		debug writefln("%x",cmp);
		debug writefln("%x",tmp);
	}
	assert(tmp == cmp);
	// rip off header ubyte
	tmp = tmp[1..$];
	int[]test2 = fromPacked!(int,fromVarint!(int))(tmp);
	assert(test == test2);
	debug writefln("");
}
