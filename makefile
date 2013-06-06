dc=dmd
Generator=conversion/common.d conversion/d1lang.d\
			 conversion/dlang.d

Library=conversion/pbbinary.d pbchild.d pbenum.d pbextension.d pbgeneral.d\
		  pbmessage.d pbroot.d d1support.d

all: libdprotobuf pbcompiler

libdprotobuf: $(Library) $(Generator)
	$(dc) -O -release -lib -oflibdprotobuf $^

pbcompiler: pbcompiler.d $(Generator) $(Library)
	$(dc) $(args) $^
