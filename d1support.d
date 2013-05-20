module ProtocolBuffer.d1support;

import std.string;

version(D_Version2) {
} else {
    int to(T)(string v) {
        return atoi(v);
    }

    string to(T)(int v) {
        return toString(v);
    }

    string to(T, S)(ulong v, S redix) {
        return toString(v, redix);
    }

    bool empty(T)(T[] v) {
        return !v.length;
    }
    bool skipOver(ref string str, string c) {
        if(str[0..c.length] == c) {
            str = str[c.length..$];
            return true;
        }
        return false;
    }
}
