module ProtocolBuffer.pbhelper;
import std.stdio;
// here is where all the encodings are defined and translated between bytes and real representations

// varint translation code
// XXX I hereby guarantee that this will be fucked up by a differing endian system XXX
byte[]toVarint(byte field,bool input) {
	return toVarint(field,cast(long)input);
}
byte[]toVarint(byte field,int input) {
	return toVarint(field,cast(long)input);
}
byte[]toVarint(byte field,long input) {
	byte[]ret;
	// get rid of any negation
	int tmp = (input<0?-input:input);
	int x = 1;
	for (;tmp >= 128;x++) {
		tmp >>= 7;
	}
	x++; // have to account for the header byte containing the field number and wire type
	ret.length = x;
	for (x = 0;x<ret.length-1;x++) {
		// set the top bit
		ret[x] = cast(byte)(1<<7);
		ret[x] |= (cast(byte)input)&0b1111111;
		input >>= 7;
	}
	// unset the top bit of the last data element
	ret[$-2] &= 0b1111111;
	// set up the header byte
	// wiretype is 0, so all we need is the shifted field number
	ret[$-1] = field<<3;
	return ret;
}

unittest {
	writefln("ProtocolBuffer.pbhelper.toVarint");
	debug writefln("toVarint(bool)...");
	byte[]tmp = toVarint(cast(byte)5,true);
	debug writefln("length");
	assert(tmp.length == 2);
	assert(tmp[0] == 1);
	debug writefln("header");
	assert(tmp[1] == cast(byte)40);
	debug writefln("toVarint(int)...");
	tmp = toVarint(cast(byte)12,300);
	debug writefln("length");
	assert(tmp.length == 3);
	byte cmp = cast(byte)0b10101100;
	debug writefln("first byte(%b): %b",cmp,tmp[0]);
	assert(tmp[0] == cmp);
	cmp = cast(byte)0b00000010;
	debug writefln("second byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);
	debug writefln("toVarint(long)...");
	//tmp = toVarint(300);
	//assert(tmp.length == 2);
	//assert(tmp[0] == 0b10101100);
	//assert(tmp[1] == 0b00000010);
}

byte[]toZigZag(byte field,int input) {
	return toVarint(field,(input<<1)^(input>>31));
}
byte[]toZigZag(byte field,long input) {
	return toVarint(field,(input<<1)^(input>>63));
}

unittest {
	writefln("ProtocolBuffer.pbhelper.toZigZag");
	debug writefln("toZigZag(int)...");
	byte[]tmp = toZigZag(cast(byte)12,0);
	debug writefln("length");
	assert(tmp.length == 2);
	byte cmp = cast(byte)0b0;
	debug writefln("first byte(%b): %b",cmp,tmp[0]);
	assert(tmp[0] == cmp);
	cmp = cast(byte)(12<<3);
	debug writefln("header byte(%b): %b",cmp,tmp[1]);
	assert(tmp[1] == cmp);

	tmp = toZigZag(cast(byte)12,-2);
	debug writefln("length");
	assert(tmp.length == 2);
	cmp = cast(byte)0b11;
	debug writefln("first byte(%b): %b",cmp,tmp[0]);
	assert(tmp[0] == cmp);
}
