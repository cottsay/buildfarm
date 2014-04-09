<?xml version='1.0' encoding='UTF-8'?>
<project>
  <actions/>
  <description>Generated job to create source rpms for "@(PACKAGE)". DO NOT EDIT BY HAND. Generated by buildfarm/scripts/create_release_jobs.py for @(USERNAME) at @(TIMESTAMP)</description>
  <logRotator>
    <daysToKeep>180</daysToKeep>
    <numToKeep>20</numToKeep>
    <artifactDaysToKeep>30</artifactDaysToKeep>
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
  <assignedNode>rpmbuild||rpmbuild-SRPMS</assignedNode>
  <canRoam>false</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers class="vector">
  </triggers>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>@(COMMAND)</command>
    </hudson.tasks.Shell>
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
} else if (manager.logContains(".*\\[Errno 16\\] error setting timestamp on file.*")) {
	reschedule_build("Internal failure in Yum")
} else if (manager.logContains(".*\\[Errno 256\\] No more mirrors to try.*")) {
	reschedule_build("Yum failed to find an appropriate package mirror")
} else if (manager.logContains(".*Cannot find a valid baseurl for repo.*")) {
	reschedule_build("Yum repo baseurl could not be found")
} else if (manager.logContains(".*OSError: \\[Errno 16\\] Device or resource busy:.*")) {
	reschedule_build("Build root was already in use")
}
</groovyScript>
      <behavior>0</behavior>
    </org.jvnet.hudson.plugins.groovypostbuild.GroovyPostbuildRecorder>
    <hudson.tasks.BuildTrigger>
      <childProjects>@(','.join(CHILD_PROJECTS))</childProjects>
      <threshold>
        <name>SUCCESS</name>
        <ordinal>0</ordinal>
        <color>BLUE</color>
      </threshold>
    </hudson.tasks.BuildTrigger>
    <hudson.plugins.descriptionsetter.DescriptionSetterPublisher>
      <regexp>package name [^\s]+ version ([^\s]+)</regexp>
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
