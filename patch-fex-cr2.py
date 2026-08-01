#!/usr/bin/env python3
# Minimal hypothesis-test patch for FEX-Emu:
# On an instruction-fetch #PF, report the real unreadable fetch address in
# si_addr AND CR2 (FEX currently reports si_addr=RIP and CR2=0). D2R's
# anti-tamper loader jumps to code that straddles a guard page and relies on
# the #PF handler reading CR2 to know which page to map; with CR2=0 it loops
# forever (STATUS_ASSERTION_FAILURE). For a page-straddling fetch the faulting
# address is the next page boundary above RIP.
import pathlib, sys, re

f = pathlib.Path("Source/Tools/LinuxEmulation/LinuxSyscalls/SignalDelegator/GuestFramesManagement.cpp")
s = f.read_text()

# 1) After si_addr = OriginalRIP, override with the real fetch-fault address for instruction #PF.
anchor = "guest_siginfo->si_addr = reinterpret_cast<void*>(ContextBackup->OriginalRIP);"
assert s.count(anchor) >= 1, "si_addr anchor not found"
inject = anchor + """
    // [thor-d2r] instruction-fetch #PF: si_addr/CR2 must be the unreadable fetch
    // address (hardware sets CR2 to the faulting linear address), not the RIP.
    // For a page-straddling fetch that is the next page boundary above RIP.
    if (Frame->SynchronousFaultData.TrapNo == FEXCore::X86State::X86_TRAPNO_PF &&
        (Frame->SynchronousFaultData.err_code & FEXCore::X86State::X86_PF_INSTR)) {
      const uint64_t PageSize = FEXCore::Utils::FEX_PAGE_SIZE;
      const uint64_t FetchFaultAddr = (ContextBackup->OriginalRIP + PageSize) & ~(PageSize - 1);
      guest_siginfo->si_addr = reinterpret_cast<void*>(FetchFaultAddr);
    }"""
s = s.replace(anchor, inject, 1)

# 2) CR2 must be the fault address, not 0.
cr2_old = "guest_uctx->uc_mcontext.gregs[FEXCore::x86_64::FEX_REG_CR2] = 0;"
assert s.count(cr2_old) == 1, "CR2 anchor not found/ambiguous"
cr2_new = ("guest_uctx->uc_mcontext.gregs[FEXCore::x86_64::FEX_REG_CR2] = "
           "reinterpret_cast<uint64_t>(guest_siginfo->si_addr); // [thor-d2r] was 0")
s = s.replace(cr2_old, cr2_new, 1)

f.write_text(s)
print("patched:", f)
print("  si_addr override + CR2=si_addr applied")
