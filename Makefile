# D1 Make file
dc?=dmd

Library=wireformat/source/dprotobuf/wireformat.d wireformat/source/dprotobuf/d1support.d

libdprotobuf: $(Library)
	$(dc) $(args) -O -release -lib -oflibdprotobufwire $^

clean:
	rm *.o *.a
