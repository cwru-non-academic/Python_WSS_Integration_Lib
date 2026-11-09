# Focused pwsh regression tests for the diagnostic helper and reviewed envelope.
# Family validators and external services are never executed by these tests.
from pathlib import Path
import unittest, subprocess, tempfile, shutil, os
HELPER=Path(__file__).resolve().parents[1]/'PhaseDiagnostics.ps1'
PWSH=shutil.which('pwsh')
NODE=shutil.which('node')
def powershell_literal(value):
    # Single-quoted PowerShell literals escape an embedded apostrophe by doubling it.
    return "'" + value.replace("'", "''") + "'"
NATIVE_EXIT_23 = ("& " + powershell_literal(NODE) + " -e 'process.exit(23)'") if NODE else '' 
def emit(family,role,op,status,error):
    return f"try {{ Write-WssCiPhaseDiagnostic -Family '{family}' -Role {role} -Operation '{op}' -Status '{status}' -Boundary -ErrorCode '{error}' }} catch {{ }}"

def envelope(body,family,role,op):
    # GH's existing pwsh epilogue remains the sole native-code exit mapper.
    start=["# WSS diagnostic envelope v1: observational only; absent completion means unknown.","$wssDiagnosticExit = Get-Variable LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue","try { . ./.github/scripts/wss-ci/PhaseDiagnostics.ps1 } catch { }",emit(family,role,op,'started','none'),"if ($null -ne $wssDiagnosticExit) { $global:LASTEXITCODE = $wssDiagnosticExit }","try {"]
    end=["} catch {","    $wssDiagnosticExit = Get-Variable LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue","    "+emit(family,role,op,'failed','terminating-error'),"    if ($null -ne $wssDiagnosticExit) { $global:LASTEXITCODE = $wssDiagnosticExit }","    throw","}","$wssDiagnosticExit = Get-Variable LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue","if ($null -ne $wssDiagnosticExit -and $wssDiagnosticExit -ne 0) {","    "+emit(family,role,op,'failed','native-nonzero'),"} else {","    "+emit(family,role,op,'completed','none'),"}","if ($null -ne $wssDiagnosticExit) { $global:LASTEXITCODE = $wssDiagnosticExit }"]
    return '\n'.join(start+['    '+l if l else '' for l in body.splitlines()]+end)+'\n'

PROLOGUE="$ErrorActionPreference = 'Stop'\n"
EPILOGUE="\nif ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }\n"
def markers(output):return [l for l in output.splitlines() if '::notice title=WSS CI phase::' in l]
def plain(output):return '\n'.join(l for l in output.splitlines() if '::notice title=WSS CI phase::' not in l)

class DiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        missing=[name for name,path in [('pwsh',PWSH),('node',NODE)] if not path]
        if missing: raise RuntimeError('Required test runtime missing: '+', '.join(missing))
    def test_executable_path_quoting(self):
        self.assertEqual(powershell_literal("/tmp/a space/owner's node"), "'/tmp/a space/owner''s node'")
    def run_case(self,body,wrapped=True,child='',prelude='',helper=True,role="'cli'"):
        with tempfile.TemporaryDirectory(prefix='phase-test-') as td:
            d=Path(td);p=d/'.github/scripts/wss-ci';p.mkdir(parents=True)
            if helper:shutil.copyfile(HELPER,p/'PhaseDiagnostics.ps1')
            (d/'child.ps1').write_text(child,encoding='utf-8')
            script=PROLOGUE+prelude+(envelope(body,'python',role,'validate-family') if wrapped else body)+EPILOGUE
            (d/'case.ps1').write_text(script,encoding='utf-8')
            return subprocess.run([PWSH,'-NoLogo','-NoProfile','-NonInteractive','-File',str(d/'case.ps1')],cwd=d,capture_output=True,text=True)
    def test_same_process_outcomes_and_stdout(self):
        cases=[("'original-output'",'',0),('& ./child.ps1',"'original-output'; exit 0",0),('& ./child.ps1',"'original-output'; exit 7",7),(NATIVE_EXIT_23,'',23),("throw 'original-error-secret'",'',1),('Write-Error original-nonterminating','',1)]
        for body,child,code in cases:
            with self.subTest(body=body,child=child):
                before=self.run_case(body,False,child);after=self.run_case(body,True,child)
                self.assertEqual(before.returncode,code);self.assertEqual(after.returncode,code)
                self.assertEqual(plain(before.stdout),plain(after.stdout));self.assertTrue(markers(after.stdout))
                self.assertNotIn('original-error-secret','\n'.join(markers(after.stdout)))
                if code==1:self.assertTrue('original-error-secret' in after.stderr or 'original-nonterminating' in after.stderr)
    def test_native_error_preference_and_strict_mode(self):
        for prelude in ("$PSNativeCommandUseErrorActionPreference=$true\n", "Set-StrictMode -Version Latest\n"):
            a=self.run_case(NATIVE_EXIT_23,False,prelude=prelude)
            z=self.run_case(NATIVE_EXIT_23,True,prelude=prelude)
            self.assertEqual(z.returncode,a.returncode)
    def test_missing_completion_is_not_called_cancellation(self):
        z=self.run_case('exit 19')
        self.assertEqual(z.returncode,19)
        self.assertEqual(len(markers(z.stdout)),1)
        self.assertIn('status=started',markers(z.stdout)[0])
        self.assertNotIn('cancel',str(markers(z.stdout)))
    def test_argument_arrays_and_script_scope(self):
        body="$sharedValue='same-scope'; & ./child.ps1 -Values @('space value','quote\"value',';literal',''); $sharedValue"
        child='param([string[]]$Values) $Values | ConvertTo-Json -Compress; $sharedValue'
        a=self.run_case(body,False,child);z=self.run_case(body,True,child)
        self.assertEqual(z.returncode,a.returncode);self.assertEqual(plain(z.stdout),plain(a.stdout))
    def test_emission_failure_does_not_mask_original(self):
        for body,expected in [("throw 'primary-preserved'",1),(NATIVE_EXIT_23,23),("'normal-body'",0)]:
            z=self.run_case(body,prelude="function Write-Host { $global:LASTEXITCODE=91; throw 'writer-fault' }\n")
            self.assertEqual(z.returncode,expected);self.assertNotIn('writer-fault',z.stderr)
            if expected==1:self.assertIn('primary-preserved',z.stderr)
    def test_missing_helper_does_not_suppress_work(self):
        for body,code in [("'normal-body'",0),(NATIVE_EXIT_23,23),("throw 'primary-preserved'",1)]:
            z=self.run_case(body,helper=False);self.assertEqual(z.returncode,code);self.assertEqual(markers(z.stdout),[])
    def test_active_operation_retained_in_outer_catch(self):
        body="try { Write-WssCiPhaseDiagnostic -Family python -Role cli -Operation validate-family-evidence -Status started -ErrorCode none } catch {}\nthrow 'private-native-evidence'"
        z=self.run_case(body);self.assertEqual(z.returncode,1)
        self.assertIn('boundary=validate-family operation=validate-family-evidence status=failed error=terminating-error',markers(z.stdout)[-1])
        self.assertNotIn('private-native-evidence','\n'.join(markers(z.stdout)))
    def test_mismatched_completions_do_not_clear_active_identity(self):
        for completion in ["-Family python -Role ros -Operation validate-family-evidence", "-Family matlab -Role cli -Operation validate-family-evidence", "-Family python -Role cli -Operation validate-intent", "-Family python -Role cli -Operation validate-family -Boundary"]:
            body="Write-WssCiPhaseDiagnostic -Family python -Role cli -Operation validate-family-evidence -Status started -ErrorCode none\nWrite-WssCiPhaseDiagnostic "+completion+" -Status completed -ErrorCode none\nthrow 'primary'"
            z=self.run_case(body)
            self.assertEqual(z.returncode,1)
            self.assertIn('operation=validate-family-evidence status=failed',markers(z.stdout)[-1])
    def test_successful_short_circuit_does_not_complete_inner_operation(self):
        child="Write-WssCiPhaseDiagnostic -Family python -Role cli -Operation inspect-reuse -Status started -ErrorCode none; exit 0"
        body="& ./child.ps1\nWrite-WssCiPhaseDiagnostic -Family python -Role cli -Operation validate-family -Boundary -Status completed -ErrorCode none\nif ($global:WssCiDiagnosticActiveOperation.Operation -cne 'inspect-reuse') { throw 'Unmatched completion cleared active state' }"
        z=self.run_case(body,child=child)
        self.assertEqual(z.returncode,0,z.stderr)
        self.assertFalse(any('operation=inspect-reuse status=completed' in x for x in markers(z.stdout)))
        self.assertIn('operation=validate-family status=completed',markers(z.stdout)[-1])
    def test_completed_operation_is_not_blamed(self):
        body="Write-WssCiPhaseDiagnostic -Family python -Role cli -Operation validate-family-evidence -Status started -ErrorCode none\nWrite-WssCiPhaseDiagnostic -Family python -Role cli -Operation validate-family-evidence -Status completed -ErrorCode none\nthrow 'later-failure'"
        z=self.run_case(body);self.assertIn('operation=validate-family status=failed',markers(z.stdout)[-1])
    def test_allowlist_rejects_untrusted_values_and_roles(self):
        body="Write-WssCiPhaseDiagnostic -Family python -Role ros -Operation validate-intent -Status started -ErrorCode none\nWrite-WssCiPhaseDiagnostic -Family python -Role 'secret%0A::error::' -Operation validate-intent -Status started -ErrorCode none\nWrite-WssCiPhaseDiagnostic -Family matlab -Role ros -Operation validate-intent -Status started -ErrorCode none\nWrite-WssCiPhaseDiagnostic -Family python -Role cli -Operation 'private-url' -Status started -ErrorCode none\nWrite-WssCiPhaseDiagnostic -Family python -Role cli -Operation validate-intent -Status failed -ErrorCode 'private-exception'"
        z=self.run_case(body);m=markers(z.stdout);self.assertEqual(len(m),3);self.assertNotIn('secret',str(m));self.assertNotIn('private',str(m))
    def test_all_roles_share_helper(self):
        for role in ('cli','ros','plan'):
            z=self.run_case("'body'",role=repr(role));self.assertEqual(z.returncode,0);self.assertTrue(all(f'role={role} ' in x for x in markers(z.stdout)))

if __name__=='__main__': unittest.main(verbosity=2)
