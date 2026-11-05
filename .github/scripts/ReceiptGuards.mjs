import {familyTargets} from './wss-ci/receipt.mjs';
export {RECEIPT_WORKFLOW,readOnlyGh,targetPolicy,runIdentity,normalRun,mergedPr,emitter,changedHead} from './wss-ci/receipt.mjs';
export const TARGETS=familyTargets('python');
export const WRAPPER=TARGETS['python-wrapper'].repository;
