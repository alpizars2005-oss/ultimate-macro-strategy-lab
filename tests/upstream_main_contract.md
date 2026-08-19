# Ultimate Macro upstream runtime contract

Strategy Lab's clean installer is built against the Ultimate Macro Main.ahk baseline used by the clean package. The relevant strategy-start ordering is:

1. RunStrategy() performs restart/join/wait-ready work.
2. If not restarting, normal maps call AlignCamera(), then CheckTheMapF().
3. activateTimescale() runs next.
4. ClickReady() runs next.
5. PlayStrategy() begins RecordedSteps and can execute SpawnTower().

Strategy Lab's pristine automatic map screenshot must therefore be injected immediately before activateTimescale(), after the camera/map verification block and before ClickReady()/PlayStrategy().

This file is documentation only; executable tests must assert the same ordering against the clean upstream Main.ahk fixture used by CI.