module ProtocolBuffer.pbhelper;

import std.conv;
import std.stdio;
import std.string;
import std.traits;
version(unittest) import std.algorithm, std.range;

// here is where all the encodings are defined and translated between bytes and real representations

// varint translation code
// this may have endian issues, maybe not, we'll see
byte[]toVarint(bool input,int field) {
	return toVarint(cast(long)(input?1:0),field);
}
byte[]toVarint(uint input,int field) {
	return toVarint(cast(long)input,field);
}
byte[]toVarint(int input,int field) {
	return toVarint(cast(long)input,field);
}
byte[]toVarint(ulong input,int field) {
	return toVarint(cast(long)input,field);
}
byte[]toVarint(long input,int field) {
	byte[]ret;
	// tack on the header and the varint
	ret = genHeader(field,0)~_toVarint(input);
	return ret;
}
byte[]_toVarint(long input) {
	byte[]ret;
	int x;
	if (input < 0) {
		// shortcut negative numbers, this is always the case
		ret.length = 10;
	} else {
		long tmp = input;
		for (x = 1;tmp >= 128;x++) {
			// arithmetic shift is fine, because we've already checked for negative numbers
			tmp >>= 7;
		}
		ret.length = x;
	}
	for (x = 0;x<ret.length;x++) {
		// set the top bit
		ret[x] = cast(byte)(1<<7);
		ret[x] |= (cast(byte)input)&0b1111111;
		input >>= 7;
	}
	// unset the top bit of the last data element
	ret[$-1] &= 0b1111111;
	return ret;
}

T fromVarint(T)(ref byte[]input)
in {
	assert(input.length);
} body {
	// find last byte
	int x;
	byte[]tmp;
	for (x = 0;x<=input.length;x++) {
		if (x == input.length) throw new Exception(
			"Found no end to varint byte string starting with: "~
			to!string(cast(ulong)input[0],16u)~" "~
			(input.length>1?to!string(cast(ulong)input[1],16u):"")~" "~
			(input.length>2?to!string(cast(ulong)input[2],16u):""));

		if (!(input[x]>>7)) {
			// we have a byte with an unset upper bit! huzzah!
			// this means we have the whole varint byte string
			tmp = input[0..x+1];
			input = input[x+1..$];
			break;
		}
	}

	long output = 0;
	for (x = to!int(tmp.length-1);x>=0;x--) {
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

int getWireType(int input) {
	return input&0b111;
}

int getFieldNumber(int input) {
	return input>>3;
}

byte[]genHeader(int field,byte wiretype) {
	return _toVarint((field<<3)|(wiretype&0x3));
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.toVarint");
	debug writefln("toVarint(bool)...");
	byte[]tmp = toVarint(true,5);
	byte cmp;
	debug writefln("length");
	assert(tmp.length == 2);
	debug writefln("header");
	assert(getFieldNumber(tmp[0]) == 5);
	cmp = cast(byte)0b00000001;
	debug writefln("first data byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	debug writefln("toVarint(int)...");
	tmp = toVarint(300,12);
	debug writefln("length");
	assert(tmp.length == 3);
	cmp = cast(byte)0b10101100;
	debug writefln("first data byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	cmp = cast(byte)0b00000010;
	debug writefln("second data byte(%b): %b",cmp,tmp[2]);
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
byte[]toSInt(int input,int field) {
	return toVarint((input<<1)^(input>>31),field);
}
byte[]toSInt(long input,int field) {
	return toVarint((input<<1)^(input>>63),field);
}

T fromSInt(T)(ref byte[]input) {
	static if (!is(T == int) && !is(T == long)) {
		throw new Exception("fromSInt only works with types int or long.");
	}
	T tmp = fromVarint!(T)(input);
	tmp = (tmp>>1)^cast(T)(tmp&0x1?0xFFFFFFFFFFFFFFFF:0);
	return tmp;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.toSInt");
	debug writefln("toSInt(int)...");
	byte[]tmp = toSInt(0,12);
	debug writefln("length");
	assert(tmp.length == 2);
	byte cmp = cast(byte)0b0;
	debug writefln("first byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	cmp = cast(byte)(12<<3);
	debug writefln("header byte(%b): %b",cmp,tmp[0]);
	assert(tmp[0] == cmp);

	debug writefln("toSInt(long)...");
	tmp = toSInt(cast(long)-2,12);
	debug writefln("length");
	assert(tmp.length == 2);
	cmp = cast(byte)0b11;
	debug writefln("first byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);

	debug writefln("fromSInt(long)...");
	// slice off header for reuse
	tmp = tmp[1..$];
	assert(-2 == fromSInt!(long)(tmp));
	assert(tmp.length == 0);
	debug writefln("");
}

// here are the remainder of the numeric types, basically just 32 and 64 bit blobs
// valid for uint, float, ulong, and double
byte[]toByteBlob(T)(T input,int field) {
	byte[]ret;
	byte[]tmp = (cast(byte*)&input)[0..T.sizeof].dup;
	version (BigEndian) {tmp.reverse;}
	ret = genHeader(field,T.sizeof==8?1:5)~tmp[0..T.sizeof];
	return ret;
}

T fromByteBlob(T)(ref byte[]input)
in {
	assert(input.length >= T.sizeof);
} body {
	T ret;
	byte[]tmp = input[0..T.sizeof]; 
	input = input[T.sizeof..$];
	version (BigEndian) {tmp.reverse;}
	(cast(byte*)&ret)[0..T.sizeof] = tmp[0..T.sizeof];
	return ret;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.byteblobs");
	byte[]tmp = toByteBlob!(double)(1.542,cast(byte)5)[1..$];
	assert(1.542 == fromByteBlob!(double)(tmp));
	assert(tmp.length == 0);
	debug writefln("");
}

// string functions!
byte[]toByteString(T)(T[]input,int field)
    if(is(Unqual!T == char) || is(Unqual!T == byte)) {
	// we need to rip off the generated header byte for code reuse, this could be done better
	byte[]tmp = _toVarint(input.length);
	return genHeader(field,2)~tmp~cast(byte[])input;
}

T[]fromByteString(T:T[])(ref byte[]input) {
	uint len = fromVarint!(uint)(input);
	if (len > input.length) {
		throw new Exception("String length exceeds length of input byte array.");
	}
	T[]ret = cast(T[])input[0..len];
	input = input[len..$];
	return ret;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.byteblobs");
	string test = "My toast has been stolen!";
	byte[]tmp = toByteString!(string )(test,cast(byte)15)[1..$];
	assert(test == fromByteString!(string )(tmp));
	assert(tmp.length == 0);
	debug writefln("");
}

byte[]ripUField(ref byte[]input,int wiretype) {
	switch(wiretype) {
	case 0:
		// snag a varint
		return _toVarint(fromVarint!(long)(input));
	case 1:
		// snag a 64bit chunk
		byte[]tmp = input[0..8];
		input = input[8..$];
		return tmp;
	case 2:
		// snag a length delimited chunk
		auto blen = fromVarint!(long)(input);
		byte[]tmp = input[0..cast(uint)blen];
		return _toVarint(blen)~tmp;
	case 5:
		// snag a 32bit chunk
		byte[]tmp = input[0..4];
		input = input[4..$];
		return tmp;
	default:
		// shit is broken....
		throw new Exception("Can't deal with wiretype "~to!string(wiretype));
	}
	throw new Exception("Wiretype "~to!string(wiretype)~" fell through switch");
}

// handle packed fields
byte[]toPacked(T:T[],alias serializer)(T[]packed,int field) {
	// zero length packed repeated fields serialize to nothing
	if (!packed.length) return null;
	byte[]ret;
	foreach(pack;packed) {
		// serialize everything, but leave off the header bytes for all of them
		ret ~= serializer(pack,field)[1..$];
	}
	// now that everything is serialized, grab the length, convert to varint, and tack on a header
	ret = genHeader(field,cast(byte)2)~_toVarint(ret.length)~ret;
	return ret;
}

T[]fromPacked(T,alias deserializer)(ref byte[]input) {
	T[]ret;
	// it's assumed that the field is already ripped off
	// grab the length to be decoded
	auto len = fromVarint!(uint)(input);
	if (input.length < len) throw new Exception("A repeated packed field specifies a length longer than available data.");
	// rip off the chunk that's ours and process the hell out of it
	byte[]own = input[0..len];
	input = input[len..$];
	while(own.length) {
		ret ~= deserializer(own);
	}
	return ret;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.packed_fields");
	int[]test = [3,270,86942];
	byte[]cmp = cast(byte[])[0x22,0x6,0x3,0x8e,0x2,0x9e,0xa7,0x5];
	byte[]tmp = toPacked!(int[],toVarint)(test,cast(byte)4);
	assert(tmp.length == 8);
	debug writeln(map!(a => format("%x", a))(cmp));
	debug writeln(map!(a => format("%x", a))(tmp));
	assert(tmp == cmp);
	// rip off header byte
	tmp = tmp[1..$];
	int[]test2 = fromPacked!(int,fromVarint!(int))(tmp);
	assert(test == test2);
	debug writefln("");
}
