-- Two exact original traffic failures, captured with normal realTime and main-loop STEP only.
local Q={}
function Q.start(g,R,H,options)
 local opts={};for k,v in pairs(options or{})do opts[k]=v end
 opts.cases=require('qa.NativeTrafficMovementCases')
 opts.expectedCaseCount=2
 opts.caseDataSha256='525869989288c69df8e5ee1cc53b88bf97ed92a8c38ba9dd0343c246f899aef4'
 opts.recordingTimeoutSeconds=360
 opts.originalNoFastSetup=true
 opts.expectedFirstActorId=25
 assert(#opts.cases==2 and opts.cases[1].id=='inherited-gastric/blood-meeting/e184/siege-siege'and opts.cases[2].id=='inherited-gastric/group/mixed-six-to-central')
 return require('qa.FullBodyMapNativeMovement').start(g,R,H,opts)
end
return Q
