<?xml version='1.0' encoding='UTF-8'?>
<project>
  <actions/>
  <description>Generated job to create binary rpms for wet package "@(PACKAGE)". DO NOT EDIT BY HAND. Generated by buildfarm/scripts/create_release_jobs.py for @(USERNAME) at @(TIMESTAMP)</description>
  <logRotator>
    <daysToKeep>90</daysToKeep>
    <numToKeep>10</numToKeep>
    <artifactDaysToKeep>10</artifactDaysToKeep>
    <artifactNumToKeep>-1</artifactNumToKeep>
  </logRotator>
  <keepDependencies>false</keepDependencies>
  <scm class="hudson.plugins.git.GitSCM" plugin="git@@1.3.0">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <name/>
        <refspec/>
        <url>git://github.com/cottsay/buildfarm.git</url>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>master</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
    <disableSubmodules>false</disableSubmodules>
    <recursiveSubmodules>false</recursiveSubmodules>
    <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
    <authorOrCommitter>false</authorOrCommitter>
    <clean>false</clean>
    <wipeOutWorkspace>false</wipeOutWorkspace>
    <pruneBranches>false</pruneBranches>
    <remotePoll>false</remotePoll>
    <ignoreNotifyCommit>false</ignoreNotifyCommit>
    <useShallowClone>false</useShallowClone>
    <buildChooser class="hudson.plugins.git.util.DefaultBuildChooser"/>
    <gitTool>Default</gitTool>
    <submoduleCfg class="list"/>
    <relativeTargetDir>monitored_vcs</relativeTargetDir>
    <reference/>
    <excludedRegions/>
    <excludedUsers/>
    <gitConfigName/>
    <gitConfigEmail/>
    <skipTag>false</skipTag>
    <includedRegions/>
    <scmName/>
  </scm>
  <assignedNode>rpmbuild||rpmbuild-@(ARCH)-@(DISTRO)</assignedNode>
  <canRoam>false</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>true</blockBuildWhenUpstreamBuilding>
  <triggers class="vector"/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.plugins.groovy.SystemGroovy plugin="groovy@@1.12">
      <scriptSource class="hudson.plugins.groovy.StringScriptSource">
        <command>
// VERFIY THAT NO UPSTREAM PROJECT IS BROKEN
import hudson.model.Result

println ""
println "Verify that no upstream project is broken"
println ""

project = Thread.currentThread().executable.project

for (upstream in project.getUpstreamProjects()) {
	if (upstream.isBuilding()) {
		println "Aborting build because upstream project '" + upstream.name + "' is currently building"
		println ""
		throw new InterruptedException()
	}
	if (upstream.getBuildsAsMap().size() &lt; 1) {
		println "Aborting build because upstream project '" + upstream.name + "' has not been built yet"
		println ""
		throw new InterruptedException()
	}
	lb = upstream.getLastBuild()
	if (!lb) {
		println "Aborting build because upstream project '" + upstream.name + "' can't provide last build"
		println ""
		throw new InterruptedException()
	}
	r = lb.getResult()
	if (!r) {
		println "Aborting build because upstream project '" + upstream.name + "' build '" + lb.getNumber() + "' can't provide last result"
		println ""
		throw new InterruptedException()
	}
	if (r.isWorseOrEqualTo(Result.FAILURE)) {
		println "Aborting build because upstream project '" + upstream.name + "' build '" + lb.getNumber() + "' has result '" + r + "'"
		println ""
		throw new InterruptedException()
	}
	println "Upstream project '" + upstream.name + "' build '" + lb.getNumber() + "' has result '" + r + "'"
}

println "All upstream projects are (un)stable"
println ""
</command>
      </scriptSource>
      <bindings/>
      <classpath/>
    </hudson.plugins.groovy.SystemGroovy>
    <hudson.tasks.Shell>
      <command>@(COMMAND)</command>
    </hudson.tasks.Shell>
    <hudson.plugins.groovy.SystemGroovy plugin="groovy@@1.12">
      <scriptSource class="hudson.plugins.groovy.StringScriptSource">
        <command>
// CHECK FOR "HASH SUM MISMATCH" AND RETRIGGER JOB
// only triggered when previous build step was successful
import java.io.BufferedReader
import java.util.regex.Matcher
import java.util.regex.Pattern

import hudson.model.Cause
import hudson.model.Result

println ""
println "Check for 'Hash Sum mismatch'"
println ""

// search build output for hash sum mismatch
r = build.getLogReader()
br = new BufferedReader(r)
pattern = Pattern.compile(".*W: Failed to fetch .* Hash Sum mismatch.*")
def line
while ((line = br.readLine()) != null) {
	if (pattern.matcher(line).matches()) {
		println "Aborting build due to 'hash sum mismatch'"
		// check if previous build was already rescheduling to avoid infinite loop
		pr = build.getPreviousBuild().getLogReader()
		if (pr) {
			pbr = new BufferedReader(pr)
			while ((line = pbr.readLine()) != null) {
				if (pattern.matcher(line).matches()) {
					println "Skip rescheduling new build since this was already a rescheduled build"
					println ""
					return
				}
			}
		}
		println "Immediately rescheduling new build..."
		println ""
		build.project.scheduleBuild(new Cause.UserIdCause())
		throw new InterruptedException()
	}
}
println "Pattern not found in build log"
println ""
</command>
      </scriptSource>
      <bindings/>
      <classpath/>
    </hudson.plugins.groovy.SystemGroovy>
  </builders>
  <publishers>
    <org.jvnet.hudson.plugins.groovypostbuild.GroovyPostbuildRecorder plugin="groovy-postbuild@@1.8">
      <groovyScript>
// CHECK FOR VARIOUS REASONS TO RETRIGGER JOB
// also triggered when a build step has failed
import hudson.model.Cause
import org.jvnet.hudson.plugins.groovypostbuild.GroovyPostbuildAction

def reschedule_build(msg) {
	pb = manager.build.getPreviousBuild()
	if (pb) {
		ba = pb.getBadgeActions()
		for (b in ba) {
			if (b instanceof GroovyPostbuildAction) {
				if (b.getText().contains(msg)) {
					manager.addInfoBadge("Log contains '" + msg + "' - skip rescheduling new build since previous build contains the same badge")
					return
				}
			}
		}
	}
	manager.addInfoBadge("Log contains '" + msg + "' - scheduled new build...")
	manager.build.project.scheduleBuild(new Cause.UserIdCause())
}

if (manager.logContains(".*hudson.plugins.git.GitException: Could not clone.*")) {
	reschedule_build("Could not clone")
} else if (manager.logContains(".*file is encrypted or is not a database.*")) {
	reschedule_build("Yum database failure")
} else if (manager.logContains(".*building: Check uncompressed DB failed.*")) {
	reschedule_build("Yum database failure")
} else if (manager.logContains(".*no such table: packages.*")) {
	reschedule_build("Yum database failure")
} else if (manager.logContains(".*Metadata file does not match checksum.*")) {
	reschedule_build("Yum database failure")
} else if (manager.logContains(".*\\[Errno 2\\] No such file or directory.*")) {
	reschedule_build("Yum database failure")
} else if (manager.logContains(".*building-source: Check uncompressed DB failed.*")) {
	reschedule_build("Yum database failure during source RPM download")
} else if (manager.logContains(".*\\[Errno 16\\] error setting timestamp on file.*")) {
	reschedule_build("Internal failure in Yum")
} else if (manager.logContains(".*\\[Errno 256\\] No more mirrors to try.*")) {
	reschedule_build("Yum failed to find an appropriate package mirror")
} else if (manager.logContains(".*Cannot find a valid baseurl for repo.*")) {
	reschedule_build("Yum repo baseurl could not be found")
} else if (manager.logContains(".*OSError: \\[Errno 16\\] Device or resource busy:.*")) {
	reschedule_build("Build root was already in use")
} else if (manager.logContains(".*\\[Errno 14\\] HTTP Error 416 - Requested Range Not Satisfiable.*")) {
	reschedule_build("Yum failed to acquire repository metadata")
}
</groovyScript>
      <behavior>0</behavior>
    </org.jvnet.hudson.plugins.groovypostbuild.GroovyPostbuildRecorder>
    <org.jvnet.hudson.plugins.groovypostbuild.GroovyPostbuildRecorder plugin="groovy-postbuild@@1.8">
      <groovyScript>
import java.io.BufferedReader
import java.util.regex.Matcher
import java.util.regex.Pattern

import hudson.model.Result

class Group {
	String label
	String badge
	String summary_icon
	Boolean mark_unstable = true
	List match_extractors = []
	List matched_items = []
	Group(String label, String badge, String summary_icon) {
		this.label = label
		this.badge = badge
		this.summary_icon = summary_icon
	}
}

// define notification groups
warnings_group = new Group(label="Warnings", badge="warning.gif", summary_icon="warning.png")
deprecations_group = new Group(label="Deprecations", badge="info.gif", summary_icon="star.png")

class MatchExtractor {
	Pattern pattern
	int next_lines
	Boolean skip_first_line
	MatchExtractor(Pattern pattern) {
		this.pattern = pattern
		this.next_lines = 0
		this.skip_first_line = false
	}
	MatchExtractor(Pattern pattern, int next_lines) {
		this.pattern = pattern
		this.next_lines = next_lines
		this.skip_first_line = false
	}
	MatchExtractor(Pattern pattern, int next_lines, Boolean skip_first_line) {
		this.pattern = pattern
		this.next_lines = next_lines
		this.skip_first_line = skip_first_line
	}
}

// define patterns and extraction parameters
// catkin_pkg warnings for invalid package.xml files
warnings_group.match_extractors.add(new MatchExtractor(pattern=Pattern.compile("WARNING\\(s\\) in .*:"), next_lines=1, skip_first_line=true))
// rpmlint error for packages that should be noarch
//warnings_group.match_extractors.add(new MatchExtractor(pattern=Pattern.compile(".*E: empty-debuginfo-package")))
// ensure package.xml is installed
warnings_group.match_extractors.add(new MatchExtractor(pattern=Pattern.compile("WARNING: package.xml not present in RPM")))
// custom catkin deprecation messages
deprecations_group.match_extractors.add(new MatchExtractor(pattern=Pattern.compile(".*\\) is deprecated.*")))
// c++ compiler warning for usage of a deprecated function
deprecations_group.match_extractors.add(new MatchExtractor(pattern=Pattern.compile(".* is deprecated \\(declared at .*")))


groups = [warnings_group, deprecations_group]

// search build output and extract found matches
r = manager.build.getLogReader()
br = new BufferedReader(r)
def line
while ((line = br.readLine()) != null) {
	for (group in groups) {
		for (me in group.match_extractors) {
			if (me.pattern.matcher(line).matches()) {
				data = []
				if (!me.skip_first_line) data.add(line)
				if (me.next_lines) {
					for (i in 1..me.next_lines) {
						line = br.readLine()
						if (line == null) break
						data.add(line)
					}
				}
				group.matched_items.add(data.join("&lt;br/&gt;"))
			}
		}
	}
}

// add badges and summaries for matches
mark_unstable = false
for (group in groups) {
	if (group.matched_items) {
		manager.addBadge(group.badge, "")
		summary_text = ""
		if (group.label) {
			summary_text += group.label + ":"
		}
		summary_text += "&lt;ul&gt;"
		for(i in group.matched_items) {
			summary_text += "&lt;li&gt;" + i + "&lt;/li&gt;"
		}
		summary_text += "&lt;/ul&gt;"
		summary = manager.createSummary(group.summary_icon)
		summary.appendText(summary_text, false)
		if (group.mark_unstable) mark_unstable = true
	}
}

// mark build as unstable
if (mark_unstable) {
	if (manager.build.getResult().isBetterThan(Result.UNSTABLE)) {
		manager.build.setResult(Result.UNSTABLE)
	}
}
</groovyScript>
      <behavior>0</behavior>
    </org.jvnet.hudson.plugins.groovypostbuild.GroovyPostbuildRecorder>
    <hudson.tasks.BuildTrigger>
      <childProjects>@(','.join(CHILD_PROJECTS))</childProjects>
      <threshold>
        <name>UNSTABLE</name>
        <ordinal>1</ordinal>
        <color>YELLOW</color>
      </threshold>
    </hudson.tasks.BuildTrigger>
    <hudson.plugins.descriptionsetter.DescriptionSetterPublisher>
      <regexp>^package name [^\s]+ version ([^\s]+)$</regexp>
      <regexpForFailed/>
      <setForMatrix>false</setForMatrix>
    </hudson.plugins.descriptionsetter.DescriptionSetterPublisher>
    <hudson.tasks.Mailer>
      <recipients>logans@@cottsay.net</recipients>
      <dontNotifyEveryUnstableBuild>false</dontNotifyEveryUnstableBuild>
      <sendToIndividuals>false</sendToIndividuals>
    </hudson.tasks.Mailer>
  </publishers>
  <buildWrappers>
@[if TIMEOUT]
    <hudson.plugins.build__timeout.BuildTimeoutWrapper>
      <timeoutMinutes>@(TIMEOUT)</timeoutMinutes>
      <failBuild>false</failBuild>
      <writingDescription>true</writingDescription>
      <timeoutType>absolute</timeoutType>
    </hudson.plugins.build__timeout.BuildTimeoutWrapper>
@[end if]
@[if SSH_KEY_ID]
    <com.cloudbees.jenkins.plugins.sshagent.SSHAgentBuildWrapper plugin="ssh-agent@@1.4.1">
      <user>@(SSH_KEY_ID)</user>
    </com.cloudbees.jenkins.plugins.sshagent.SSHAgentBuildWrapper>
@[end if]
  </buildWrappers>
</project>
