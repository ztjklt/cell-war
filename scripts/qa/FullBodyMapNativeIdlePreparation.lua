-- Opt-in native acceptance of the exact former pancreas idle-blocker failure.
local Q={}
function Q.start(g,R,H,options)
 local opts={};for k,v in pairs(options or{})do opts[k]=v end
 opts.cases=require('qa.NativeIdlePreparationCases')
 opts.populateIdle=require('qa.NativeIdlePreparationPopulation')
 opts.expectedCaseCount=1
 opts.caseDataSha256='e88da06486ae3555ab4deb4de36b22449aeadee5f5f4a16e10aceb2e2d8cc4ba'
 assert(#opts.cases==1 and opts.cases[1].id=='native-idle-preparation/pancreas/scout-blocks-siege/pancreas.candidate.1')
 return require('qa.FullBodyMapNativeMovement').start(g,R,H,opts)
end
return Q
