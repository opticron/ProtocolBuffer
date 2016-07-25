# D1 Make file
dc?=dmd

Library=wireformat/source/dprotobuf/wireformat.d

libdprotobuf: $(Library)
	$(dc) $(args) -O -release -lib -oflibdprotobufwire $^

clean:
	rm *.o *.a
