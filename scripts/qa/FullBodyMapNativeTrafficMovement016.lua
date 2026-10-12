-- Three exact original traffic failures, captured with normal realTime and main-loop STEP only.
local Q={}
function Q.start(g,R,H,options)
 local opts={};for k,v in pairs(options or{})do opts[k]=v end
 opts.cases=require('qa.NativeTrafficMovementCases016')
 opts.expectedCaseCount=3
 opts.caseDataSha256='9e4e63da402ad257f764c37b6690094ac42f15902394c5d59d395acbc6b74696'
 opts.recordingTimeoutSeconds=360
 opts.originalNoFastSetup=true
 opts.expectedFirstActorId=25
 assert(#opts.cases==3 and opts.cases[1].id=='inherited-gastric/blood-meeting/e184/siege-siege'and opts.cases[2].id=='inherited-gastric/group/mixed-six-to-central'and opts.cases[3].id=='inherited-gastric/membrane-meeting/study.stomach.wall_service.outer/siege-siege')
 return require('qa.FullBodyMapNativeMovement').start(g,R,H,opts)
end
return Q
