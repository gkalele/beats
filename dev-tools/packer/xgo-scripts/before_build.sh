#!/bin/sh

set -e

BEAT_PATH=/go/src/${1}
# BEATNAME is in the $PACK variable
BEATNAME=$PACK

if [ $BEATNAME = "packetbeat" ]; then
	patch -p1 < /gopacket_pcap.patch
fi

cd $BEAT_PATH

PREFIX=/build

# Add data to the home directory
mkdir -p $PREFIX/homedir
make install-home HOME_PREFIX=$PREFIX/homedir

# Compile the import_dashboards binary for the requested targets.
if [ -d $BEAT_PATH/../libbeat/ ]; then
	# official Beats have libbeat in the top level folder
	LIBBEAT_PATH=$BEAT_PATH/../libbeat/
elif [ -d $BEAT_PATH/vendor/github.com/elastic/beats/libbeat/ ]; then
	# community Beats have libbeat vendored
	LIBBEAT_PATH=$BEAT_PATH/vendor/github.com/elastic/beats/libbeat/
else
	echo "Couldn't find the libbeat location"
	exit 1
fi

for TARGET in $TARGETS; do
	echo "Compiling import_dashboards for $TARGET"
	XGOOS=`echo $TARGET | cut -d '/' -f 1`
	XGOARCH=`echo $TARGET | cut -d '/' -f 2`

	GOOS=$XGOOS GOARCH=$XGOARCH go build -ldflags "-X main.beat=${BEATNAME}" -o $PREFIX/import_dashboards-$XGOOS-$XGOARCH $LIBBEAT_PATH/dashboards/import_dashboards.go
done

if [ -n "BUILDID" ]; then
    echo "$BUILDID" > $PREFIX/homedir/.build_hash.txt
fi

# Install gotpl. Clone and copy needed as go-yaml is behind a proxy which doesn't work
# with git 1.7
git clone https://github.com/tsg/gotpl.git /go/src/github.com/tsg/gotpl
mkdir -p /go/src/gopkg.in/yaml.v2

cp -r $LIBBEAT_PATH/../vendor/gopkg.in/yaml.v2 /go/src/gopkg.in/
go install github.com/tsg/gotpl

# Append doc versions to package.yml
cat ${LIBBEAT_PATH}/docs/version.asciidoc >> ${PREFIX}/package.yml
# Make variable naming of doc-branch compatible with gotpl. Generate and copy README.md into homedir
sed -i -e 's/:doc-branch/doc_branch/g' ${PREFIX}/package.yml
/go/bin/gotpl ${LIBBEAT_PATH}/../dev-tools/packer/readme.md.j2 < ${PREFIX}/package.yml > ${PREFIX}/homedir/README.md

# Copy template
cp $BEATNAME.template.json $PREFIX/$BEATNAME.template.json
cp $BEATNAME.template-es2x.json $PREFIX/$BEATNAME.template-es2x.json

# linux
cp $BEATNAME.yml $PREFIX/$BEATNAME-linux.yml
cp $BEATNAME.full.yml $PREFIX/$BEATNAME-linux.full.yml

# darwin
cp $BEATNAME.yml $PREFIX/$BEATNAME-darwin.yml
cp $BEATNAME.full.yml $PREFIX/$BEATNAME-darwin.full.yml

# win
cp $BEATNAME.yml $PREFIX/$BEATNAME-win.yml
cp $BEATNAME.full.yml $PREFIX/$BEATNAME-win.full.yml

# Contains beat specific adjustments. As it is platform specific knowledge, it should be in packer not the beats itself
PREFIX=$PREFIX make before-build
