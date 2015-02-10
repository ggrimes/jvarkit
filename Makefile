#
# Starting moving from ANT to make
#
SHELL=/bin/bash
this.makefile=$(lastword $(MAKEFILE_LIST))
this.dir=$(dir $(realpath ${this.makefile}))

#need local settings ? create a file 'local.mk' in this directory
ifneq ($(realpath local.mk),)
include $(realpath local.mk)
endif

# proxy for curl, etc...
curl.proxy=$(if ${http.proxy.host}${http.proxy.port},-x "${http.proxy.host}:${http.proxy.port}",)
xjc.proxy=$(if ${http.proxy.host}${http.proxy.port}, -httpproxy "${http.proxy.host}:${http.proxy.port}" ,)

ANT?=ant
JAVAC?=${JAVA_HOME}/bin/javac
JAVA?=${JAVA_HOME}/bin/java
JAR?=${JAVA_HOME}/bin/jar
htsjdk.version?=1.128
htsjdk.home?=${this.dir}htsjdk-${htsjdk.version}
htsjdk.jars=$(addprefix ${htsjdk.home}/dist/,$(addsuffix .jar,commons-jexl-2.1.1 commons-logging-1.1.1 htsjdk-${htsjdk.version} snappy-java-1.0.3-rc3))
src.dir=${this.dir}src/main/java
generated.dir=${this.dir}src/main/generated-sources
tmp.dir=${this.dir}_tmp-${htsjdk.version}
dist.dir?=${this.dir}dist-${htsjdk.version}
biostars.id=59647 86363 86480 84452 90204 94573 103303 106668

## http://stackoverflow.com/questions/9551416
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)

define compile-htsjdk-cmd

## 1 : target name
## 2 : qualified main class name
## 3 : other deps

$(1)  : ${htsjdk.jars} \
		${generated.dir}/java/com/github/lindenb/jvarkit/util/htsjdk/HtsjdkVersion.java \
		$(if $(3),$(3), $(addsuffix .java,$(addprefix ${src.dir}/,$(subst .,/,$(2)))) )
	mkdir -p ${tmp.dir}/META-INF ${dist.dir}
	cp src/main/resources/messages/messages.properties ${tmp.dir}
	${JAVAC} -d ${tmp.dir} -g -classpath "$$(subst $$(SPACE),:,$$(filter %.jar,$$^))" -sourcepath ${src.dir}:${generated.dir}/java $$(filter %.java,$$^)
	#create META-INF/MANIFEST.MF
	echo "Manifest-Version: 1.0" > ${tmp.dir}/META-INF/MANIFEST.MF
	echo "Main-Class: $(2)" >> ${tmp.dir}/META-INF/MANIFEST.MF
	echo "Class-Path: $$(filter %.jar,$$^) ${dist.dir}/$(1).jar" | fold -w 71 | awk '{printf("%s%s\n",(NR==1?"": " "),$$$$0);}' >>  ${tmp.dir}/META-INF/MANIFEST.MF
	echo -n "Git-Hash: " >> ${tmp.dir}/META-INF/MANIFEST.MF
	$$(if $$(realpath .git/refs/heads/master),cat $$(realpath .git/refs/heads/master), echo "undefined")  >> ${tmp.dir}/META-INF/MANIFEST.MF 
	echo -n "Compile-Date: " >> ${tmp.dir}/META-INF/MANIFEST.MF
	date +%Y-%m-%d:%H-%m-%S >> ${tmp.dir}/META-INF/MANIFEST.MF
	#create jar
	${JAR} cfm ${dist.dir}/$(1).jar ${tmp.dir}/META-INF/MANIFEST.MF  -C ${tmp.dir} .
	#create bash executable
	echo '#!/bin/bash' > ${dist.dir}/$(1)
	echo '${JAVA} -Xmx500m -cp "$$(subst $$(SPACE),:,$$(filter %.jar,$$^)):${dist.dir}/$(1).jar" $(2) $$*' > ${dist.dir}/$(1)
	chmod  ugo+rx ${dist.dir}/$(1)
	#cleanup
	rm -rf ${tmp.dir}

endef

#
# $1 :biostar post-id
# $2: other deps
#
define compile_biostar_cmd
$(call compile-htsjdk-cmd,biostar$(1),com.github.lindenb.jvarkit.tools.biostar.Biostar$(1),$(2))
endef

APPS=vcfresetvcf sam2tsv

.PHONY: all $(APPS) clean biostars

all: $(APPS)

biostars: $(foreach B, ${biostars.id} , biostar$(B) )

$(eval $(call compile-htsjdk-cmd,sam2tsv,com.github.lindenb.jvarkit.tools.sam2tsv.Sam2Tsv,${src.dir}/com/github/lindenb/jvarkit/tools/sam2tsv/Sam2Tsv.java))
$(eval $(call compile-htsjdk-cmd,vcfresetvcf,com.github.lindenb.jvarkit.tools.misc.VcfRemoveGenotypeIfInVcf))
$(eval $(foreach B, ${biostars.id} , $(call compile_biostar_cmd,$B)))

$(filter-out ${htsjdk.home}/dist/htsjdk-${htsjdk.version}.jar  ,${htsjdk.jars}) : ${htsjdk.home}/dist/htsjdk-${htsjdk.version}.jar 
	touch --no-create $@

${htsjdk.home}/dist/htsjdk-${htsjdk.version}.jar : ${htsjdk.home}/build.xml
	echo "Compiling htsjdk with $${JAVA_HOME} = ${JAVA_HOME}"
	(cd ${htsjdk.home} && ${ANT} )

${htsjdk.home}/build.xml : 
	mkdir -p $(dir ${htsjdk.home})
	rm -rf $(dir ${htsjdk.home})${htsjdk.version}.zip $(dir $@) 
	echo "Downloading HTSJDK ${htsjdk.version} with curl"
	curl  ${curl.proxy} -o $(dir ${htsjdk.home})${htsjdk.version}.zip -L "https://github.com/samtools/htsjdk/archive/${htsjdk.version}.zip"
	unzip $(dir ${htsjdk.home})${htsjdk.version}.zip -d $(dir ${htsjdk.home})
	find ${htsjdk.home} -exec touch '{}'  ';'
	rm -f $(dir ${htsjdk.home})${htsjdk.version}.zip

${generated.dir}/java/com/github/lindenb/jvarkit/util/htsjdk/HtsjdkVersion.java : ${htsjdk.home}/build.xml
	mkdir -p $(dir $@)
	echo "package com.github.lindenb.jvarkit.util.htsjdk;" > $@
	echo '@javax.annotation.Generated("jvarkit")' >> $@
	echo 'public class HtsjdkVersion{ private HtsjdkVersion(){}' >> $@
	echo 'public static String getVersion() {return "${htsjdk.version}";}' >> $@
	echo 'public static String getHome() {return "${htsjdk.home}";}' >> $@
	echo '}'  >> $@

## API EVS
src/main/generated-sources/java/edu/washington/gs/evs/package-info.java :
	mkdir -p ${generated.dir}/java
	${JAVA_HOME}/bin/xjc ${xjc.proxy} -d ${generated.dir}/java \
		-p edu.washington.gs.evs \
		"http://evs.gs.washington.edu/wsEVS/EVSDataQueryService?wsdl"

clean:
	rm -rf ${dist.dir}

