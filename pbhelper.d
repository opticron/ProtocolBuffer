module ProtocolBuffer.pbhelper;
import std.stdio;
import std.string;
// here is where all the encodings are defined and translated between bytes and real representations

// varint translation code
// XXX I hereby guarantee that this will be fucked up by a differing endian system XXX
byte[]toVarint(byte field,bool input) {
	return toVarint(field,cast(long)(input?1:0));
}
byte[]toVarint(byte field,uint input) {
	return toVarint(field,cast(long)input);
}
byte[]toVarint(byte field,int input) {
	return toVarint(field,cast(long)input);
}
byte[]toVarint(byte field,ulong input) {
	return toVarint(field,cast(long)input);
}
byte[]toVarint(byte field,long input) {
	byte[]ret;
	int x;
	if (input < 0) {
		// shortcut negative numbers, this is always the case
		ret.length = 11;
	} else {
		long tmp = input;
		for (x = 1;tmp >= 128;x++) {
			// arithmetic shift is fine, because we've already checked for negative numbers
			tmp >>= 7;
		}
		x++; // have to account for the header byte containing the field number and wire type
		ret.length = x;
	}
	for (x = 1;x<ret.length;x++) {
		// set the top bit
		ret[x] = cast(byte)(1<<7);
		ret[x] |= (cast(byte)input)&0b1111111;
		input >>= 7;
	}
	// unset the top bit of the last data element
	ret[$-1] &= 0b1111111;
	// set up the header byte
	// wiretype is 0, so all we need is the shifted field number
	ret[0] = cast(byte)(field<<3);
	return ret;
}

long fromVarint(inout byte[]input)
in {
	assert(input.length);
} body {
	// find last byte
	int x;
	byte[]tmp;
	for (x = 0;x<=input.length;x++) {
		if (x == input.length) throw new Exception(
			"Found no end to varint byte string starting with: "~
			toString(cast(ulong)input[0],16u)~" "~
			(input.length>1?toString(cast(ulong)input[1],16u):"")~" "~
			(input.length>2?toString(cast(ulong)input[2],16u):""));

		if (!(input[x]>>7)) {
			// we have a byte with an unset upper bit! huzzah!
			// this means we have the whole varint byte string
			tmp = input[0..x+1];
			input = input[x+1..$];
			break;
		}
	}

	long output = 0;
	for (x = tmp.length-1;x>=0;x--) {
		output |= (tmp[x]&0b1111111);
		if (x==0) {
			// we're done, so jump out so we can return values
			break;
		}
		output <<= 7;
	}
	return output;
}

int intFromVarint(inout byte[]input) {
	long tmp = fromVarint(input);
	if (tmp <= int.max && tmp >= int.min) {
		return cast(int)tmp;
	}
	throw new Exception("Integer parse is not within the valid range for int32!");
}

uint uintFromVarint(inout byte[]input) {
	long tmp = fromVarint(input);
	if (tmp <= uint.max && tmp >= uint.min) {
		return cast(int)tmp;
	}
	throw new Exception("Integer parse is not within the valid range for uint32!");
}

int getWireType(byte input) {
	return input&0b111;
}

int getFieldNumber(byte input) {
	return (input>>3)&0b1111;
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.toVarint");
	debug writefln("toVarint(bool)...");
	byte[]tmp = toVarint(cast(byte)5,true);
	byte cmp;
	debug writefln("length");
	assert(tmp.length == 2);
	debug writefln("header");
	assert(getFieldNumber(tmp[0]) == 5);
	cmp = cast(byte)0b00000001;
	debug writefln("first data byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	debug writefln("toVarint(int)...");
	tmp = toVarint(cast(byte)12,300);
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
	long ret = fromVarint(tmp);
	assert(ret == 300);

	debug writefln("Checking max/min edges...");
	tmp = toVarint(cast(byte)5,ulong.max);
	tmp = tmp[1..$];
	assert(ulong.max == fromVarint(tmp));

	tmp = toVarint(cast(byte)5,long.min);
	tmp = tmp[1..$];
	assert(long.min == fromVarint(tmp));

	tmp = toVarint(cast(byte)5,int.min);
	tmp = tmp[1..$];
	assert(int.min == intFromVarint(tmp));

	tmp = toVarint(cast(byte)5,uint.max);
	tmp = tmp[1..$];
	uint uitmp = uintFromVarint(tmp);
	debug writefln("%d should be %d",uitmp,uint.max);
	assert(uint.max == uitmp);


	debug writefln("");
}

byte[]toSInt(byte field,int input) {
	return toVarint(field,(input<<1)^(input>>31));
}
byte[]toSInt(byte field,long input) {
	return toVarint(field,(input<<1)^(input>>63));
}

long fromSInt(byte[]input) {
	long tmp = fromVarint(input);
	return (tmp>>1)^cast(long)(tmp&0x1?0xFFFFFFFFFFFFFFFF:0);
}

unittest {
	writefln("unittest ProtocolBuffer.pbhelper.toSInt");
	debug writefln("toSInt(int)...");
	byte[]tmp = toSInt(cast(byte)12,0);
	debug writefln("length");
	assert(tmp.length == 2);
	byte cmp = cast(byte)0b0;
	debug writefln("first byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	cmp = cast(byte)(12<<3);
	debug writefln("header byte(%b): %b",cmp,tmp[0]);
	assert(tmp[0] == cmp);

	debug writefln("toSInt(long)...");
	tmp = toSInt(cast(byte)12,cast(long)-2);
	debug writefln("length");
	assert(tmp.length == 2);
	cmp = cast(byte)0b11;
	debug writefln("first byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);

	debug writefln("fromSInt(long)...");
	// slice off header for reuse
	tmp = tmp[1..$];
	assert(-2 == fromSInt(tmp));
	debug writefln("");
}
