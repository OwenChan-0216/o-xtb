! This file is part of xtb.
!
! Copyright (C) 2017-2020 Stefan Grimme
!
! xtb is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! xtb is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with xtb.  If not, see <https://www.gnu.org/licenses/>.

! Modified by the o-xtb landscape task suite, 2026.

subroutine citation(iunit)
integer,intent(in) :: iunit
write(iunit,'(3x,a)') &
   "Cite this work as:", &
   "* C. Bannwarth, E. Caldeweyher, S. Ehlert, A. Hansen, P. Pracht,",&
   "  J. Seibert, S. Spicher, S. Grimme, WIREs Comput. Mol. Sci., 2020, 11,",&
   "  e01493. DOI: 10.1002/wcms.1493",&
   "",&
   "for GFN2-xTB:",&
   "* C. Bannwarth, S. Ehlert and S. Grimme., J. Chem. Theory Comput., 2019,",&
   "  15, 1652-1671. DOI: 10.1021/acs.jctc.8b01176",&
   "for GFN1-xTB:",&
   "* S. Grimme, C. Bannwarth, P. Shushkov, J. Chem. Theory Comput., 2017,",&
   "  13, 1989-2009. DOI: 10.1021/acs.jctc.7b00118", &
   "for GFN0-xTB:",&
   "* P. Pracht, E. Caldeweyher, S. Ehlert, S. Grimme, ChemRxiv, 2019, preprint.",&
   "  DOI: 10.26434/chemrxiv.8326202.v1",&
   "for GFN-FF:",&
   "* S. Spicher and S. Grimme, Angew. Chem. Int. Ed., 2020, 59, 15665-15673.",&
   "  DOI: 10.1002/anie.202004239", &
   "",&
   "for ALPB and GBSA implicit solvation:",&
   "* S. Ehlert, M. Stahn, S. Spicher, S. Grimme, J. Chem. Theory Comput.,", &
   "  2021, 17, 4250-4261. DOI: 10.1021/acs.jctc.1c00471", &
   "",&
   "for ddCOSMO and CPCM-X implicit solvation:",&
   "* M. Stahn, S. Ehlert, S. Grimme, J. Phys. Chem. A,", &
   "  2023, XX, XXXX-XXXX. DOI: 10.1021/acs.jpca.3c04382", &
   "",&
   "for DFT-D4:",&
   "* E. Caldeweyher, C. Bannwarth and S. Grimme, J. Chem. Phys., 2017,",&
   "  147, 034112. DOI: 10.1063/1.4993215", &
   "* E. Caldeweyher, S. Ehlert, A. Hansen, H. Neugebauer, S. Spicher,", &
   "  C. Bannwarth and S. Grimme, J. Chem. Phys., 2019, 150, 154122.", &
   "  DOI: 10.1063/1.5090222", &
   "* E. Caldeweyher, J.-M. Mewes, S. Ehlert and S. Grimme, Phys. Chem. Chem. Phys.",&
   "  2020, 22, 8499-8512. DOI: 10.1039/D0CP00502A",&
   "",&
   "for sTDA-xTB:",&
   "* S. Grimme and C. Bannwarth, J. Chem. Phys., 2016, 145, 054103.",&
   "  DOI: 10.1063/1.4959605",&
   "",&
   "in the mass-spec context:",&
   "* V. Asgeirsson, C. Bauer and S. Grimme, Chem. Sci., 2017, 8, 4879.",&
   "  DOI: 10.1039/c7sc00601b",&
   "* J. Koopman and S. Grimme, ACS Omega 2019, 4, 12, 15120-15133.",&
   "  DOI: 10.1021/acsomega.9b02011",&
   "",&
   "for metadynamics refer to:",&
   "* S. Grimme, J. Chem. Theory Comput., 2019, 155, 2847-2862", &
   "  DOI: 10.1021/acs.jctc.9b00143", &
   "",&
   "for SPH calculations refer to:",&
   "* S. Spicher and S. Grimme, J. Chem. Theory Comput., 2021, 17, 1701-1714", &
   "  DOI: 10.1021/acs.jctc.0c01306", &
   "",&
   "for ONIOM refer to:",&
   "* C. Plett, A. Katbashev, S. Ehlert, S. Grimme, M. Bursch,",&
   "  Phys. Chem. Chem. Phys., 2023, 25, 17860-17868. DOI: 10.1039/D3CP02178E",&
   "",&
   "for DIPRO refer to:",&
   "* J. Kohn, N. Gildemeister, S. Grimme, D. Fazzi, A. Hansen,",&
   "  J. Chem. Phys. 159, 144106 (2023). DOI: 10.1063/5.0167484",&
   "",&
   "for PTB refer to:",&
   "* S. Grimme, M. Mueller, A. Hansen, J. Chem. Phys., 2023, 158, 124111.",&
   "  DOI: 10.1063/5.0137838",&
   "",&
   "for O1NumHess refer to:",&
   "* B. Wang, S. Luo, Z. Wang, W. Liu,",&
   "  J. Chem. Theory Comput. 21, 10893-10909.",&
   "  DOI: 10.1021/acs.jctc.5c01354",&
   "",&
   "with help from (in alphabetical order)",&
   "P. Atkinson, C. Bannwarth, F. Bohle, G. Brandenburg, E. Caldeweyher,", &
   "M. Checinski, S. Dohm, S. Ehlert, S. Ehrlich, M. Friede, T. Froitzheim,", &
   "I. Gerasimov, C. Hölzer, A. Katbashev, J. Kohn, J. Koopman, C. Lavigne,", &
   "S. Lehtola, F. März, M. Müller, F. Musil, H. Neugebauer, J. Pisarek,", &
   "C. Plett, P. Pracht, F. Pultar, J. Seibert, L. M. Seidler, P. Shushkov, S. Spicher,", &
   "M. Stahn, M. Steiner, T. Strunk, J. Stückrath, T. Rose, and J. Unsleber", &
   ""
end subroutine citation

subroutine help(iunit)
   implicit none
   integer, intent(in) :: iunit
   write(iunit,'(a)') &
   "Usage: xtb [options] <geometry> [options]", &
   "",&
   "<geometry> may be provided as valid TM coordinate file (*coord in Bohr),",&
   "in xmol format (*.xyz in Ångström), sdf or mol file format, PDB format",&
   "genFormat input or Vasp's POSCAR format.",&
   "",&
   "For a full list visit: https://grimme-lab.github.io/mctc-lib/page/index.html", &
   "",&
   "Options:",&
   "",&
   "-c, --chrg, --charge INT",&
   "    specify molecular charge as INT, overrides .CHRG file and xcontrol option",&
   "",&
   "--ceh <grad> [REAL]",&
   "    calculate CEH (Charge-Extended Hückel model) charges and write them to the ceh.charges file",&
   "    optionally, calculate numerical gradients and write them to the ceh.charges.numgrad file",&
   "    with an adjustable step size for the numerical gradients.",&
   "",&
   "-u, --uhf INT",&
   "    specify number of unpaired electrons as INT, overrides .UHF file and xcontrol option",&
   "    (default: 0 (singlet) for even electron number, 1 (doublet) for odd electron number)",&
   "",&
   "--gfn INT",&
   "    specify parametrisation of GFN-xTB: 0 (GFN0-xTB), 1 (GFN1-xTB), 2",&
   "    (GFN2-xTB, the default) or ff (GFN-FF, the same as --gfnff); any",&
   "    other value is refused with an error",&
   "",&
   "--gfn0",&
   "    use the GFN0-xTB (EHT) Hamiltonian, the same as --gfn 0; a discouraged", &
   "    spelling, the run prints a warning and asks for --gfn 0",&
   "",&
   "--gfn1",&
   "    use the GFN1-xTB Hamiltonian, the same as --gfn 1; a discouraged", &
   "    spelling, the run prints a warning and asks for --gfn 1",&
   "",&
   "--gfn2",&
   "    use the GFN2-xTB Hamiltonian (the default), the same as --gfn 2",&
   "",&
   "--gfnff, --gff",&
   "    specify parametrisation of GFN-FF",&
   "",&
   "--mcgfnff",&
   "    use the MC-GFN-FF force field",&
   "",&
   "--iff",&
   "    use the IFF (intermolecular force field) calculator; the fragment", &
   "    sizes are taken from --nat",&
   "",&
   "--nat LIST",&
   "    number of atoms per fragment of the IFF calculation, comma separated",&
   "",&
   "--tblite,",&
   "    use tblite library as implementation for xTB, please note that solvation is not yet implemented within tblite",&
   "",&
   "--color SCHEME",&
   "    colour scheme of the tblite output, one of auto (follow the build", &
   "    feature, default), always or never (tblite builds only)",&
   "",&
   "--dipro [REAL]",&
   "    calculate DIPRO coupling integrals (tblite builds only); the optional", &
   "    REAL is the coupling threshold (default 0.1)",&
   "",&
   "--ptb,",&
   "    performs single-point calculation with the density tight-binding method PTB.", &
   "    Provides electronic structure and properties, such as, e.g., atomic charges, bond orders, and dipole moments,", & 
   "    but does not provide any energy-related properties, such as, e.g., total energy, nuclear gradients, or vibrational frequencies.", &
   "",&
   "--tm",&
   "    use the external Turbomole program for the energy and the gradient",&
   "",&
   "--orca",&
   "    use the external ORCA program for the energy and the gradient",&
   "",&
   "--mopac",&
   "    use the external MOPAC program for the energy and the gradient",&
   "",&
   "--driver [EXECUTABLE]",&
   "    use an external driver program for the energy and the gradient; the", &
   "    optional argument names the executable to run (there is no built-in default)", &
   "",&
   "--spinpol,",&
   "    enables spin-polarization for xTB methods (tblite required)",&
   "",&
   "--oniom METHOD LIST", &
   "    use subtractive embedding via ONIOM method. 'METHOD' is given as 'inner:outer'", &
   "    where 'inner' can be 'orca', 'turbomole', 'gfn2', 'gfn1', or 'gfnff' and", &
   "    'outer' can be 'gfn2', 'gfn1', or 'gfnff'.", &
   "    The inner region is given as a comma separated indices directly in the commandline", &
   "    or in a file with each index on a separate line.", &
   "",&
   "--cut",&
   "    ONIOM: cut the inner region out of the input and stop without a", &
   "    calculation",&
   "",&
   "--efield REAL,REAL,REAL",&
   "    static electric field in Cartesian coordinates, overrides '.EFIELD' file,",&
   "    works only via tblite for the xTB Hamiltonians, or with GFN-FF and PTB.",&
   "",&
   "--etemp REAL",&
   "    electronic temperature (default = 300K)",&
   "",&
   "--esp",&
   "    calculate electrostatic potential on VdW-grid",&
   "",&
   "--stm",&
   "    calculate STM image",&
   "",&
   "-a, --acc REAL",&
   "    accuracy for SCC calculation, lower is better (default = 1.0)",&
   "",&
   "--iterations, --maxiterations INT",&
   "    maximum number of SCC iterations per single point calculation", &
   "    (default = 250)",&
   "",&
   "--vparam FILE",&
   "    Parameter file for vTB calculation",&
   "",&
   "--alpb SOLVENT [STATE]",&
   "    analytical linearized Poisson-Boltzmann (ALPB) model,",&
   "    available solvents are acetone, acetonitrile, aniline, benzaldehyde,",&
   "    benzene, ch2cl2, chcl3, cs2, dioxane, dmf, dmso, ether, ethylacetate, furane,", &
   "    hexandecane, hexane, methanol, nitromethane, octanol, woctanol, phenol, toluene,",&
   "    thf, water.",&
   "    The solvent input is not case-sensitive. The Gsolv",&
   "    reference state can be chosen as reference, bar1M, or gsolv (default).",&
   "",&
   "-g, --gbsa SOLVENT [STATE]",&
   "    generalized born (GB) model with solvent accessable surface (SASA) model,",&
   "    available solvents are acetone, acetonitrile, benzene (only GFN1-xTB), CH2Cl2,",&
   "    CHCl3, CS2, DMF (only GFN2-xTB), DMSO, ether, H2O, methanol,",&
   "    n-hexane (only GFN2-xTB), THF and toluene.",&
   "    The solvent input is not case-sensitive.", &
   "    The Gsolv reference state can be chosen as reference, bar1M, or gsolv (default).",&
   "",&
   "--gbe SOLVENT/EPSILON",&
   "    generalized Born for finite epsilon (GBe) solvation model (tblite required),", &
   "    includes only the electrostatic solvation contribution (no SASA model),", &
   "    available solvents are all solvents that are available for alpb.", &
   "    Additionally, the dielectric constant can be set manually.", &
   "",&
   "--gb SOLVENT/EPSILON",&
   "    generalized Born (GB) solvation model (tblite required),", &
   "    includes only the electrostatic solvation contribution (no SASA model),", &
   "    available solvents are all solvents that are available for alpb.", &
   "    Additionally, the dielectric constant can be set manually.", &
   "",&
   "--cosmo SOLVENT/EPSILON",&
   "    domain decomposition conductor-like screening model (ddCOSMO),",&
   "    available solvents are all solvents that are available for alpb.",&
   "    Additionally, the dielectric constant can be set manually or an ideal conductor", &
   "    can be chosen by setting epsilon to infinity.",&
   "",&
   "--tmcosmo SOLVENT/EPSILON",&
   "    same as --cosmo, but uses TM convention for writing the .cosmo files.",&
   "",&
   "--cpcmx SOLVENT",&
   "    extended conduction-like polarizable continuum solvation model (CPCM-X),",&
   "    available solvents are all solvents included in the Minnesota Solvation Database.",&
   "",&
   "--cma",&
   "    shifts molecule to center of mass and transforms cartesian coordinates into the",&
   "    coordinate system of the principle axis (not affected by ‘isotopes’-file).",&
   "",&
   "--pop",&
   "    requests printout of Mulliken population analysis",&
   "",&
   "--molden",&
   "    requests printout of molden file",&
   "",&
   "--dipole",&
   "    requests dipole printout",&
   "",&
   "--raman", &
   "    requests Raman spectrum calculation via combination of GFN2-xTB and PTB",&
   "    using the temperature 'REAL' (default 298.15 K) and the wavelength of the",& 
   "    incident laser which must be given in nm 'REAL' (default 514 nm).",&
   "",&
   "--alpha",&
   "    requests the extension of electrical properties to static molecular dipole polarizabilities. ",&
   "",&
   "--wbo",&
   "    requests Wiberg bond order printout",&
   "",&
   "--lmo",&
   "    requests localization of orbitals",&
   "",&
   "--fod",&
   "    requests FOD calculation",&
   "",&
   "--coffee",&
   "    ignore the input geometry and run the built-in caffeine molecule", &
   "    (a debugging helper)",&
   "",&
   "--enso",&
   "    write the machine readable thermochemistry xtb_enso.json in a", &
   "    frequency run",&
   "",&
   "--scc, --sp",&
   "    performs a single point calculation",&
   "",&
   "--vip",&
   "    performs calculation of ionisation potential. This needs the param_ipea-xtb.txt",&
   "    parameters and a GFN1 Hamiltonian.",&
   "",&
   "--vea",&
   "    performs calculation of electron affinity. This needs the param_ipea-xtb.txt",&
   "    parameters and a GFN1 Hamiltonian.",&
   "",&
   "--vipea",&
   "    performs calculation of electron affinity and ionisation potential.",&
   "    This needs the param_ipea-xtb.txt parameters and a GFN1 Hamiltonian.",&
   "",&
   "--vfukui",&
   "    performs calculation of Fukui indices.",&
   "",&
   "--vomega",&
   "    performs calculation of electrophilicity index. This needs the param_ipea-xtb.txt",&
   "    parameters and a GFN1 Hamiltonian.",&
   "",&
   "--grad",&
   "    performs a gradient calculation",&
   "",&
   "-o, --opt [LEVEL]",&
   "    optimize the geometry with the landscape task suite (stage 3); the legacy", &
   "    ANCopt is reachable as --opt --method ancopt, and the level keyword follows", &
   "    the upstream names crude, sloppy, loose, lax, normal (default), tight,", &
   "    verytight, extreme, the spelling vtight and the suite-only superloose; the", &
   "    run echoes the level it uses",&
   "",&
   "-3, -2, -1, 0, 1, 2, 3",&
   "    numeric aliases of the level keywords.  For --opt and --ohess they map", &
   "    onto the landscape levels (-3/-2 superloose, -1 loose, 0 normal, 1 tight,", &
   "    2/3 vtight); the native run types --bhess, --omd and --metaopt use", &
   "    their own table (-3 crude, -2 sloppy, 3 extreme)", &
   "",&
   "--method NAME",&
   "    select the method of the current landscape run type; the value domain is", &
   "    filtered by the run type and an unknown or mismatched name aborts the run.", &
   "    --lopt and --lscan accept the minimisers sd, cg, lbfgs, bfgs, diis, rfo;", &
   "    --lts accepts the saddle searches prfo, bprfo, dimer, neb, cineb, autoneb,", &
   "    string, gsm; --lirc accepts the integrators gs, hpc, lqa, eulerpc; auto keeps", &
   "    the default of the task.  With --opt and --ohess the native engines ancopt", &
   "    (alias rf), lancopt (alias l-ancopt), fire (alias inertial) and pbc_lbfgs are", &
   "    accepted; a landscape name selects the suite that the redeployed --opt runs.", &
   "    --method is the canonical name of --lopt-engine, --lscan-method,", &
   "    --lts-method and --lirc-method: the same value is idempotent, a different", &
   "    value through two of the flags aborts the run.  The name is not", &
   "    case-sensitive",&
   "",&
   "--ljson",&
   "    write the structured result landscape_<task>.json for every task: native", &
   "    (--sp, --grad, --opt, --hess, --ohess, --md, ...) and landscape (--lopt,", &
   "    --lscan, --lts, --lirc, --lvib).  The document carries a uniform core", &
   "    block (task, status, converged, energy, n_atoms, geometry, provenance)", &
   "    plus the task specific counters and convergence history, so one parser", &
   "    reads every task; it is meant for regression comparison and is written", &
   "    independently of the other output files (format 2)",&
   "",&
   "--lopt",&
   "    minimize the geometry with the landscape task suite (src/landscape); the", &
   "    algorithm is selected with --lopt-engine and the thresholds with --lopt-level",&
   "    an xcontrol $scan block is not executed by this run type and aborts the run", &
   "    (use --opt --method ancopt for that block, or --lscan with --lscan-coord)", &
   "",&
   "--lopt-engine NAME",&
   "    minimisation algorithm of the landscape suite, one of sd, cg, lbfgs,", &
   "    bfgs, diis or rfo (default lbfgs).  Alias of --method.  The name is", &
   "    not case-sensitive", &
   "",&
   "--lopt-level LEVEL",&
   "    convergence level of the landscape suite (thresholds, energy tolerance, SCC", &
     "    accuracy and the step budget), one of superloose, loose,", &
   "    normal (default), tight or vtight.  The level name is not case-sensitive", &
   "",&
   "--lopt-hessian SOURCE",&
   "    Hessian backend of the landscape suite (minimisation and Hessian", &
   "    based steps), one of numerical (default, central differences of the", &
   "    electronic gradient), model (Lindh-D2 model Hessian) or file (read the", &
   "    Hessian written by an earlier run, named by --lopt-hessian-file)",&
   "",&
   "--lopt-max-steps N",&
   "    step budget of the minimisation; the default is derived from the",&
   "    convergence level (3 steps per atom at level normal, clamped to",&
   "    200..10000), --cycles and the level change it",&
   "",&
   "--lopt-hess-step VALUE",&
   "    finite difference step of the numerical Hessian in bohr (default 0.005);", &
   "    only --lopt-engine rfo builds a numerical Hessian; the other five", &
   "    engines (including the default lbfgs) never do, and the value is", &
   "    ignored for --lopt-hessian model or file.  The run echoes the", &
   "    effective value and marks it as unused in that case.  The canonical", &
   "    spelling, mirrored by --lscan-hess-step and by --lts-hess-step /", &
   "    --lirc-hess-step / --lvib-hess-step for the other landscape tasks", &
   "",&
   "--lopt-sccacc VALUE",&
   "    SCC accuracy of the displaced single points of the numerical Hessian", &
   "    (default 0.3), consumed by the same engine and Hessian source as", &
   "    --lopt-hess-step", &
   "",&
   "--lopt-restart MODE",&
   "    wavefunction restart policy of the engine, off (default), pin or warm", &
   "",&
   "--lscan",&
   "    scan an internal coordinate (distance, angle or dihedral) with the landscape", &
   "    task suite (src/landscape); a relaxed scan relaxes each scan point under a", &
   "    constraint potential, a rigid scan only moves the geometry. The result is", &
   "    written to xtbscan.log with the de-biased energy of every frame, together", &
   "    with a report of the constraint residual and, for a bidirectional scan, of", &
   "    the hysteresis between the forward and the reverse branch",&
   "",&
   "--lscan-coord TYPE",&
   "    type of the first scanned coordinate, one of distance, angle or dihedral",&
   "    (the type name is not case-sensitive)", &
   "",&
   "--lscan-atoms LIST",&
   "    1-based atom indices of the first coordinate, comma or blank separated", &
   "    (two for a distance, three for an angle, four for a dihedral)",&
   "",&
   "--lscan-step VALUE",&
   "    step size of the first coordinate in angstrom (distance) or degree", &
   "    (angle/dihedral)",&
   "",&
   "--lscan-nstep N",&
   "    number of steps of the first coordinate",&
   "",&
   "--lscan-coord2, --lscan-atoms2, --lscan-step2, --lscan-nstep2",&
   "    same as above for the second scanned coordinate; any of them switches the", &
   "    scan to a two-dimensional Cartesian product grid",&
   "",&
   "--lscan-mode MODE",&
   "    scan mode, relaxed (default) or rigid (not case-sensitive)", &
   "",&
   "--lscan-method NAME",&
   "    inner minimiser of a relaxed scan, one of sd, cg, lbfgs (default), bfgs,", &
   "    diis or rfo.  Alias of --method.  The name is not case-sensitive", &
   "",&
   "--lscan-level LEVEL",&
   "    convergence level of the inner minimisation (thresholds, energy tolerance,", &
     "    SCC accuracy and the step budget), one of superloose, loose,", &
   "    normal (default), tight or vtight",&
   "",&
   "--lscan-ndim N",&
   "    number of scanned coordinates, 1 (default) or 2",&
   "",&
   "--lscan-restart MODE",&
   "    wavefunction policy of the scan points, off (default), pin or warm", &
   "    (warm_start reuses only the geometry, never the wavefunction)",&
   "",&
   "--lscan-oneway",&
   "    scan the forward branch only (no reverse branch, no hysteresis report)",&
   "",&
   "--lscan-cold-start",&
   "    start every scan point from the input geometry instead of the previous point",&
   "",&
   "--lscan-fc VALUE",&
   "    force constant of the constraint potential in hartree/bohr^2 (default 0.5)",&
   "",&
   "--lscan-expo VALUE",&
   "    exponent of the constraint potential (default 2.0)",&
   "",&
   "--lscan-max-steps N",&
   "    step budget of the inner relaxation of every scan point; the default", &
   "    is derived from the convergence level (3 steps per atom at level", &
   "    normal, clamped to 200..10000), --cycles and the level change it", &
   "",&
   "--lscan-hess-step VALUE",&
   "    finite difference step of the numerical Hessian of the scan points in", &
   "    bohr (default 0.005); only an inner minimiser of --lscan-method rfo", &
   "    builds a numerical Hessian (the default lbfgs never does), a rigid", &
   "    scan has no inner minimisation at all, and the value is ignored for", &
   "    --lscan-hessian model or file.  The run echoes the effective value", &
   "    and marks it as unused in those cases", &
   "",&
   "--lscan-sccacc VALUE",&
   "    SCC accuracy of the displaced single points of the numerical Hessian", &
   "    of the scan points (default 0.3), consumed by the same inner", &
   "    minimiser and Hessian source as --lscan-hess-step", &
   "",&
   "--lscan-hessian SOURCE",&
   "    Hessian backend of the scan points, one of numerical (default), model or file",&
   "",&
   "--lscan-hessian-file NAME",&
   "    file read by --lscan-hessian file (TURBOMOLE Hessian layout)", &
   "",&
   "--lopt-hessian-file NAME",&
   "    file read by --lopt-hessian file (TURBOMOLE Hessian layout)", &
   "",&
   "--lts",&
   "    transition state search with the landscape task suite (src/landscape);", &
   "    writes xtbts.xyz and xtbts.log and confirms the imaginary mode count", &
   "",&
   "--lts-method NAME",&
   "    search method, one of prfo (default), bprfo (restricted step), dimer", &
   "    (first derivatives only, no Hessian), neb, cineb (climbing image NEB),", &
   "    autoneb (incremental path building) or string / gsm (growing string).", &
   "    Alias of --method.  The method name is not case-sensitive", &
   "",&
   "--lts-trust VALUE",&
   "    initial trust radius of the step in bohr (default 0.37795)", &
   "",&
   "--lts-trust-max VALUE",&
   "    upper bound of the trust radius in bohr (default 1.8897)", &
   "",&
   "--lts-hlow VALUE",&
   "    curvature floor of the downhill modes in hartree/bohr^2 (default 0.01)", &
   "",&
   "--lts-max-steps N",&
   "    maximum number of macro iterations; the default is derived from the", &
   "    convergence level (3 steps per atom at level normal, clamped to", &
   "    200..10000), --cycles and the level change it", &
   "",&
   "--lts-level LEVEL",&
   "    convergence level (thresholds, energy tolerance, SCC accuracy and the step", &
     "    budget), one of superloose, loose, normal, tight, vtight", &
   "",&
   "--lts-mode-overlap-min VALUE",&
   "    mode following guard: reselect the transition vector below this overlap (default 0.3)", &
   "",&
   "--lts-alpha VALUE",&
   "    fraction of the trust radius assigned to the uphill subspace by bprfo (default 0.5)", &
   "",&
   "--lts-micro-cycles N",&
   "    maximum number of restricted step micro iterations (default 50)", &
   "",&
   "--lts-target-mode N",&
   "    which negative mode is followed, 1 = most negative (default 1)", &
   "",&
   "--lts-init-mode MODE",&
   "    initial transition vector, h0 (most negative Hessian mode, default) or force", &
   "    (largest Cartesian gradient component direction)", &
   "",&
   "--lts-escape-step VALUE",&
   "    displacement along the lowest internal mode in bohr (default 0.2), applied", &
   "    when the start geometry is a minimum so P-RFO has a direction to ascend", &
   "    along; 0 disables the escape", &
   "",&
   "--lts-delta VALUE",&
   "    dimer separation, the distance of each image from the midpoint in bohr",&
   "    (default 0.018897, i.e. 0.01 angstrom)", &
   "",&
   "--lts-dr VALUE",&
   "    finite difference step of the dimer translation probe in bohr (default 0.0018897)", &
   "",&
   "--lts-rot-max-iter N",&
   "    maximum number of dimer rotations per macro iteration (default 5)", &
   "",&
   "--lts-rot-alpha VALUE",&
   "    damping of the dimer rotation angle of Eq. 13, 1 = undamped (default 0.5)", &
   "",&
   "--lts-rot-frms VALUE",&
   "    RMS torque below which the dimer rotation converged, in hartree/bohr (default 2.65e-4)", &
   "",&
   "--lts-ninit MODE",&
   "    initial dimer axis, random (default, seeded by --lts-seed) or force",&
   "    (largest Cartesian gradient component direction)", &
   "",&
   "--lts-seed N",&
   "    seed of the random initial dimer axis (default 42)", &
   "",&
   "--lts-step-max VALUE",&
   "    maximum dimer translation step in bohr (default 0.28346)", &
   "",&
   "--lts-step0 VALUE",&
   "    upper bound of the first dimer translation in bohr (default 0.37795);", &
   "    the dR curvature probe can shorten the actual first displacement", &
   "",&
   "--lts-translate-max-iter N",&
   "    maximum number of quick-min displacement updates per dimer translation (default 1)", &
   "",&
   "--lts-recalc N",&
   "    recompute the exact Hessian every N macro steps, 0 disables (default 1)", &
   "",&
   "--lts-no-verify",&
   "    skip the frequency confirmation of the located stationary point", &
   "",&
   "--lts-no-rigid",&
   "    keep the rigid body (translation/rotation) components in the Cartesian step", &
   "",&
   "--lts-restart MODE",&
   "    wavefunction restart policy of the engine, off (default), pin or warm", &
   "",&
   "--lts-hessian SOURCE",&
   "    Hessian backend, one of numerical (default), model (Lindh-D2) or file", &
   "",&
   "--lts-hessian-file NAME",&
   "    file read by --lts-hessian file (TURBOMOLE Hessian layout)", &
   "",&
   "--lts-hess-step VALUE",&
   "    finite difference step of the numerical confirmation Hessian in bohr", &
   "    (default 0.005); the canonical name of --lts-step", &
   "",&
   "--lts-step VALUE",&
   "    alias of --lts-hess-step: finite difference step of the numerical", &
   "    confirmation Hessian in bohr (default 0.005);", &
   "    a mode inside 0 +/- 3 cm^-1 is re-decided with 0.002 bohr and sccacc 0.1", &
   "",&
   "--lts-sccacc VALUE",&
   "    SCC accuracy of the displaced single points of the confirmation Hessian (default 0.3)", &
   "",&
   "--lts-product NAME",&
   "    product endpoint of a chain-of-states search (neb, cineb, autoneb, string,", &
   "    gsm): a single frame xyz with the same atoms in the same order", &
   "",&
   "--lts-images N",&
   "    number of images of a band, the two fixed endpoints included (default 9);", &
   "    for autoneb it is the requested final number of images", &
   "",&
   "--lts-kmin VALUE, --lts-kmax VALUE",&
   "    lower/upper spring constant of the dynamic springs in hartree/bohr^2", &
   "    (defaults 1e-2 and 1e-1, calibrated on the analytic LEPS surface)", &
   "",&
   "--lts-kdecay VALUE",&
   "    decay factor of the dynamic spring formula (default 0.5)", &
   "",&
   "--lts-no-dynamic-k",&
   "    use the single spring constant k_max for every image", &
   "",&
   "--lts-climb",&
   "    switch on the climbing image stage (CI-NEB); implied by --lts-method", &
   "    cineb, autoneb, string and gsm", &
   "",&
   "--lts-climb-switch VALUE",&
   "    band force (hartree/bohr) below which the climbing image is ignited", &
   "    (default 9.7234e-3, the standard 0.5 eV/angstrom)", &
   "",&
   "--lts-no-idpp",&
   "    straight linear interpolation instead of the IDPP initial path", &
   "",&
   "--lts-no-align",&
   "    do not Kabsch align the images before every band evaluation", &
   "",&
   "--lts-relax-ends",&
   "    relax the two endpoints with the minimiser before the search", &
   "",&
   "--lts-max-displ VALUE",&
   "    upper bound of one displacement component of a band step in bohr", &
   "    (default 0.37795)", &
   "",&
   "--lts-frms-avg VALUE, --lts-frms-max VALUE",&
   "    band convergence thresholds of the average and the largest per-image", &
   "    force RMS in hartree/bohr (defaults 3e-4 and 1e-3)", &
   "",&
   "--lts-autoneb-nstart N",&
   "    number of images of the coarse start path of an AutoNEB run (default 5)", &
   "",&
   "--lts-autoneb-max-paths N",&
   "    hard upper bound of the number of images of an AutoNEB path (default 10);", &
   "    a request above it is an error", &
   "",&
   "--lts-autoneb-max-depth N",&
   "    hard upper bound of the number of image insertion stages (default 5)", &
   "",&
   "--lts-autoneb-restart NAME",&
   "    multi-frame xyz path of an earlier AutoNEB run (its path_autoneb.xyz),", &
   "    adopted as the initial path so the completed stages are not repeated", &
   "",&
   "--lts-string-nnodes N",&
   "    target number of nodes of the growing string, endpoints included (default 9)", &
   "",&
   "--lts-string-grow-tol VALUE",&
   "    norm threshold of the growth indicator of Eq. 7 in hartree/bohr (default 5e-3)", &
   "",&
   "--lts-string-ds VALUE",&
   "    arc length increment of one growth step of the string in bohr (default 0.5)", &
   "",&
   "--lts-string-nu2 VALUE",&
   "    curvature floor nu2 of the node spacing condition R > |gradV.tau|/(2 nu2)", &
   "    in hartree/bohr^2 (default 0.05)", &
   "",&
   "--lts-string-grow-steps N",&
   "    maximum perpendicular relaxation iterations of one frontier node (default 200)", &
   "",&
   "--lts-no-string-spline",&
   "    central difference tangents of the string instead of the cubic spline tangent", &
   "",&
   "--lts-string-history",&
   "    print the growth history (position and perpendicular force of every node)", &
   "",&
   "--lirc",&
   "    intrinsic reaction coordinate with the landscape task suite (src/landscape);", &
   "    the input geometry is the transition state and must have exactly one imaginary", &
   "    mode; writes irc_forward.xyz, irc_backward.xyz, irc_path.xyz and irc.log", &
   "",&
   "--lirc-method NAME",&
   "    integration method, one of hpc (Hessian based predictor-corrector, default:", &
   "    most accurate and 1.98 E/g per point), lqa (Page-McIver analytic quadratic", &
   "    propagation, cheapest at 1.00 E/g), eulerpc (Euler predictor-corrector, use a", &
   "    step of 0.20 or less) or gs (Gonzalez-Schlegel sphere relaxation, compatible", &
   "    reference; 1.9-2.1 E/g per point and the largest path deviation, validated", &
   "    for steps up to 0.15).", &
   "    Alias of --method.  The method name is not case-sensitive", &
   "",&
   "--lirc-step VALUE",&
   "    step length in bohr*amu^1/2 (mass weighted arc length, default 0.10; use 0.05", &
   "    for a tight path). The clean range is 0.05-0.15 for --lirc-method gs, whose", &
   "    macro step stalls in a two cycle from 0.20 on (--lirc-osc-window); hpc and", &
   "    eulerpc are correct at 0.20. The guard only detects the cancelling (limit", &
   "    cycle) subclass of the stall: a large step can still end far from the", &
   "    minimum (measured 0.236 bohr at 0.40 forward)", &
   "",&
   "--lirc-max-steps N",&
   "    maximum number of macro steps of one direction; the default is", &
   "    derived from the convergence level (3 steps per atom at level", &
   "    normal, clamped to 200..10000), --cycles and the level change it", &
   "",&
   "--lirc-level LEVEL",&
   "    convergence level of the endpoint relaxation (thresholds, energy tolerance,", &
     "    SCC accuracy and the step budget), one of superloose, loose,", &
   "    normal, tight, vtight (the IRC path itself is left by the gradient and", &
   "    energy-rise termination signals, see --lirc-grad-tol/--lirc-e-rise)", &
   "",&
   "--lirc-swap",&
   "    exchange the forward and backward directions defined by the phase convention", &
   "",&
   "--lirc-oneway",&
   "    integrate the forward direction only", &
   "",&
   "--lirc-target-mode N",&
   "    which negative mode defines the initial direction, 1 = most negative (default 1)", &
   "",&
   "--lirc-micro-cycles N",&
   "    maximum number of Gonzalez-Schlegel micro cycles per macro step (default 20)", &
   "",&
   "--lirc-micro-thresh VALUE",&
   "    convergence threshold of the sphere relaxation in bohr*amu^1/2 (default 1e-3)", &
   "",&
   "--lirc-euler-n N",&
   "    Euler/Simpson substeps of the analytic LQA propagation (default 5000)", &
   "",&
   "--lirc-loose-cycles N",&
   "    EulerPC coarse phase: use the plain Euler prediction for the first N macro", &
   "    steps, 0 disables the coarse phase (default 3)", &
   "", &
   "--lirc-mbs-tol VALUE",&
   "    acceptance threshold of the modified Bulirsch-Stoer corrector in", &
   "    bohr*amu^1/2 (default 1e-5; the HPC paper uses 1e-6)", &
   "",&
   "--lirc-mbs-max-k N",&
   "    maximum extrapolation level of the mBS corrector (default 15)", &
   "",&
   "--lirc-mbs-points N",&
   "    base number of Euler substeps of the mBS corrector (default 20)", &
   "",&
   "--lirc-dwi-n N",&
   "    capacity of the DWI surface fit (default 4). The interpolant is two point by", &
   "    construction (current and predicted point), so any N >= 2 is equivalent;", &
   "    N < 2 is rejected", &
   "",&
   "--lirc-e-rise N",&
   "    termination signal (c): stop after N consecutive rising energies (default 3). A", &
   "    large N does not guarantee running to the step budget: the GS limit cycle", &
   "    guard (--lirc-osc-window) is an independent signal (d)", &
   "",&
   "--lirc-erise-steps N",&
   "    alias of --lirc-e-rise N", &
   "", &
   "--lirc-grad-tol VALUE",&
   "    termination signal (b): stop when the RMS gradient per Cartesian component", &
   "    falls below this value in hartree/bohr (default 1e-3)", &
   "", &
   "--lirc-osc-window N",&
   "    limit cycle guard of the GS macro step: leave the path after N consecutive", &
   "    macro steps that cancel each other (default 8, 0 disables the guard). The", &
   "    guard is bitwise inert on every validated path and truncates the stalled", &
   "    87 macro step walk of Mueller-Brown at step 0.20 to 13 steps. The endpoint", &
   "    it returns is not a converged path point - it is one phase of the", &
   "    oscillation, about one step length away from the minimum - so the run is", &
   "    reported as incomplete and reached_min stays false unless an endpoint", &
   "    relaxation confirms the geometry. Only --lirc-method gs is affected", &
   "", &
   "--lirc-adaptive",&
   "    opt-in adaptive step length of the GS macro step (default off): halve the", &
   "    effective step length (floor: a sixteenth of --lirc-step) at the first", &
   "    cancelling macro step pair, so a large step recovers accuracy instead of", &
   "    being truncated at the first cancellation (the guard still applies once", &
   "    the floor is reached). It changes the validated small step paths and is", &
   "    therefore a re-baseline; every reduction is printed. Only --lirc-method", &
   "    gs is affected; the other methods ignore it", &
   "", &
   "--lirc-recalc N",&
   "    rebuild the exact Hessian every N macro steps, -1 disables (default -1). Pure", &
   "    Bofill updates are sufficient for short paths; long or strongly curved paths", &
   "    drift and need an explicit --lirc-recalc 5 .. 10", &
   "",&
   "--lirc-no-endpoint-relax",&
   "    do not relax the two endpoints to assign them to a minimum", &
   "",&
   "--lirc-endpoint-relax",&
   "    relax the two endpoints to assign them to a minimum (default; the explicit", &
   "    flag restores it after a --lirc-no-endpoint-relax)", &
   "", &
   "--lirc-rmsd-end VALUE",&
   "    Kabsch aligned RMSD between an endpoint and its relaxed minimum below which", &
   "    the endpoint counts as having reached a minimum, in bohr (default 0.18897).", &
   "    The criterion needs a relaxed endpoint and is skipped (and reported as", &
   "    skipped) with --lirc-no-endpoint-relax", &
   "",&
   "--lirc-hessian SOURCE",&
   "    Hessian backend, one of numerical (default), model (Lindh-D2) or file", &
   "",&
   "--lirc-hessian-file NAME",&
   "    file read by --lirc-hessian file (TURBOMOLE Hessian layout)", &
   "",&
   "--lirc-hess-step VALUE",&
   "    finite difference step of the numerical Hessian in bohr (default 0.005);", &
   "    the canonical name of --lirc-step-hess (not to be confused with", &
   "    --lirc-step, the arc length of the reaction path)", &
   "",&
   "--lirc-step-hess VALUE",&
   "    alias of --lirc-hess-step: finite difference step of the numerical", &
   "    Hessian in bohr (default 0.005)", &
   "",&
   "--lirc-sccacc VALUE",&
   "    SCC accuracy of the displaced single points of the Hessian (default 0.3)", &
   "",&
   "--lirc-restart MODE",&
   "    wavefunction restart policy of the engine, off (default), pin or warm", &
   "",&
   "--lvib",&
   "    harmonic frequencies, normal modes and thermochemistry with the landscape task", &
   "    suite (src/landscape); writes vibspectrum, vib_normal_modes, g98.out and hessian", &
   "    with the names and formats of --hess", &
   "    an xcontrol $thermo block (temp, sthr, imagthr, scale) is honoured unless", &
   "    the matching --lvib-temp, --lvib-rotor-cutoff, --lvib-imag-cutoff or", &
   "    --lvib-freq-scal option is given: explicit command line > $thermo > default", &
   "",&
   "--lvib-hessian SOURCE",&
   "    Hessian backend of the frequency task, one of numerical (default, central", &
   "    differences of the electronic gradient), model (Lindh-D2) or file (read the", &
   "    Hessian of an earlier run)", &
   "",&
   "--lvib-hessian-file NAME",&
   "    file read by --lvib-hessian file (TURBOMOLE Hessian layout)", &
   "",&
   "--lvib-hess-step VALUE",&
   "    finite difference step of the numerical Hessian in bohr (default 0.005);", &
   "    the canonical name of --lvib-step", &
   "",&
   "--lvib-step VALUE",&
   "    alias of --lvib-hess-step: finite difference step of the numerical", &
   "    Hessian in bohr (default 0.005)", &
   "",&
   "--lvib-sccacc VALUE",&
   "    SCC accuracy of the displaced single points of the numerical Hessian (default 0.3)", &
   "",&
   "--lvib-restart MODE",&
   "    wavefunction restart policy of the engine, off (default), pin or warm.", &
   "    The finite difference sequence resets the wavefunction to the state it", &
   "    entered the Hessian with before every displacement, so warm and pin", &
   "    hand the provider the same start and produce a byte identical", &
   "    `hessian` file; only off is distinguishable (it records the cold start", &
   "    wavefunction).  The two spellings are kept, the equivalence is", &
   "    asserted by the xtb/landscape-lvib-restart-warm check",&
   "",&
   "--lvib-odlr",&
   "    request the ODLR approximation; not implemented, the run reports the request", &
   "",&
   "--lvib-no-project",&
   "    do not project the translations and rotations out of the Hessian", &
   "",&
   "--lvib-temp VALUE",&
   "    temperature of the thermodynamic table in K (default 298.15)", &
   "",&
   "--lvib-rotor-cutoff VALUE",&
   "    rotor cutoff of the quasi-RRHO entropy treatment in cm^-1 (default 50.0)", &
   "",&
   "--lvib-imag-cutoff VALUE",&
   "    imaginary frequency cutoff in cm^-1 (default -20.0, needs the minus sign)", &
   "",&
   "--lvib-freq-scal VALUE",&
   "    frequency scaling factor of the thermochemistry (default 1.0)", &
   "",&
   "--cycles [int]",&
   "    maximum number of optimization cycles.",&
   "",&
   "--hess",&
   "    perform a numerical hessian calculation on input geometry",&
   "",&
   "--ohess [LEVEL]",&
   "    minimize the geometry with the landscape task suite and run its harmonic", &
   "    frequency analysis (the legacy ancopt(3) plus numerical Hessian path is", &
   "    --ohess --method ancopt)", &
   "",&
   "--bhess [LEVEL]",&
   "    perform a biased numerical hessian calculation on an ancopt(3) optimized geometry",&
   "",&
   "    Molecular Hessian runs with more than one atom, no frozen atoms, and no periodicity",&
   "    automatically print compliance constants, relaxed force constants, and bond local-mode",&
   "    frequencies, and write compliance.dat.",&
   "",&
   "--o1nh",&
   "    perform the numerical hessian calculation using the ODLR approximation (O1NumHess)",&
   "",&
   "--imagmin REAL",&
   "    magnitudes below this value (cm⁻¹) are ignored in the O1NumHess",&
   "    imaginary frequency repair (default 5)",&
   "",&
   "--imagmax REAL",&
   "    deepest imaginary frequency (cm⁻¹) considered in the O1NumHess",&
   "    imaginary frequency repair (default 200)",&
   "",&
   "--md",&
   "    molecular dynamics simulation on start geometry",&
   "",&
   "--metadyn [int]",&
   "    meta dynamics simulation on start geometry, saving int snapshots of the", &
   "    trajectory to bias the simulation",&
   "",&
   "--bias-input, --gesc FILE",&
   "    file with the RMSD bias of the metadynamics run (--metadyn)",&
   "",&
   "--omd",&
   "    molecular dynamics simulation on ancopt(3) optimized geometry,", &
   "    a loose optimization level will be chosen",&
   "",&
   "--metaopt [LEVEL]",&
   "    call ancopt(3) to perform a geometry optimization, then try to find other", &
   "    minimas by meta dynamics",&
   "",&
   "--path [FILE]",&
   "    use meta dynamics to calculate a path from the input geometry to the given", &
   "    product structure",&
   "",&
   "--modef INT",&
   "    modefollowing algorithm. INT specifies the mode that should be used for the", &
   "    modefollowing.",&
   "",&
   "--screen",&
   "    optimisation loop over an ensemble: QMDFF generates it when a file", &
   "    'solvent' exists, otherwise it is read from the file xtbscreen.xyz",&
   "",&
   "--mdopt",&
   "    re-optimise the structures of the molecular dynamics trajectory xtb.trj", &
   "    at the current optimisation level; the energies are written to", &
   "    xtb_ensemble.xyz",&
   "",&
   "--siman",&
   "    conformational search by simulated annealing; the run type is not", &
   "    registered in this build, so the run aborts",&
   "",&
   "--ewin REAL",&
   "    energy window of the conformational search (default 20.0)",&
   "",&
   "--gmd",&
   "    deprecated; the run aborts with a message",&
   "",&
   "-I, --input FILE",&
   "    use FILE as input source for xcontrol(7) instructions",&
   "",&
   "--namespace STRING",&
   "    give this xtb(1) run a namespace. All files, even temporary ones, will be named",&
   "    according to STRING (might not work everywhere).",&
   "",&
   "--[no]copy",&
   "    copies the xcontrol file at startup (default = true)",&
   "",&
   "--[no]restart",&
   "    restarts calculation from xtbrestart (default = true)",&
   "",&
   "-P, --parallel INT",&
   "    number of parallel processes",&
   "",&
   "--blas-threads N",&
   "    set the thread count of the linear algebra backend (OpenBLAS or MKL)",&
   "    at run time and print the value read back; without the flag the",&
   "    backend is left untouched (default)",&
   "",&
   "--define",&
   "    performs automatic check of input and terminate",&
   "",&
   "--json",&
   "    write xtbout.json file",&
   "",&
   "--wrtopo LIST",&
   "    comma separated topology printouts, from etot, gnorm, nb, bpair, alist,", &
   "    blist, tlist, vtors, vbond, vangl, hbbond, eeq and json (json selects", &
   "    all of them); a misspelled keyword aborts the run",&
   "",&
   "--nocellopt",&
   "    do not optimise the lattice of a periodic system, the cell is kept", &
   "    fixed (default: the cell is optimised)",&
   "",&
   "--citation",&
   "    print citation and terminate",&
   "",&
   "--license",&
   "    print license and terminate",&
   "",&
   "--version",&
   "    print the version banner and terminate",&
   "",&
   "-v, --verbose",&
   "    be more verbose (not supported in every unit)",&
   "",&
   "-V, --very-verbose",&
   "    be very verbose (this also enables the verbose output)",&
   "",&
   "--ceasefiles",&
   "    reduce the amount of output and files written",&
   "",&
   "--strict",&
   "    turns all warnings into hard errors",&
   "",&
   "-h, --help",&
   "    show help page",&
   "",&
   "Useful Maschine Settings: ",&
   "",&
   "export OMP_NUM_THREADS=<NCORE>,1",&
   "export OMP_STACKSIZE=4G",&
   "ulimit -s unlimited",&
   "",&
   "A threaded BLAS is the largest performance trap on multi core machines: the",&
   "OpenMP threads and the BLAS thread pool multiply, and an idle pool spins",&
   "between the calls.  Measured on a 24 atom anthracene GFN2 single point at",&
   "OMP_NUM_THREADS=8, five runs with the minimum taken on an idle machine,",&
   "these are the settings that recover the loss, in this order of effect:",&
   "",&
   "  1) export OPENBLAS_NUM_THREADS=1        12 ms   strongest",&
   "  2) --blas-threads 1                     99 ms   8.3x slower than 1)",&
   "     + OMP_WAIT_POLICY=PASSIVE            20 ms   1.7x slower than 1)",&
   "     no flag (pool left at eight)         583 ms",&
   "",&
   "OPENBLAS_NUM_THREADS is consumed while the OpenBLAS pool is created, in an",&
   "ELF constructor that runs before main, so the shell has to export it before",&
   "the process starts - the program cannot set it in time (OMP_WAIT_POLICY and",&
   "GOMP_SPINCOUNT are read at start-up as well).  --blas-threads resizes the",&
   "work partition of that pool from inside the run, but the pool itself was",&
   "already built at eight threads, and what remains is the OpenMP teams",&
   "spinning between the calls, which the wait policy and the spin count",&
   "control.",&
   "",&
   "The same limit can be requested from inside the program, without any",&
   "environment variable:",&
   "",&
   "xtb mol.xyz --blas-threads 1",&
   "",&
   "It resolves the OpenBLAS (or MKL) runtime API with dlopen/dlsym, calls it and",&
   "prints the value read back; it does nothing at all unless the flag is given.",&
   "A backend that exports no such symbol - the reference BLAS, or a statically",&
   "linked BLAS, whose symbols are invisible to dlsym - is reported as 'no",&
   "OpenBLAS or MKL symbol found' and the run continues.  Both API pairs are",&
   "resolved by symbol name (openblas_set_num_threads and its getter, and the",&
   "oneMKL pair mkl_set_num_threads / mkl_get_max_threads that threadpoolctl",&
   "reads); this build links OpenBLAS, so the MKL branch has not been run here",&
   "against a real oneMKL and is documented from the oneMKL names only.",&
   "",&
   "-P and --parallel set the OpenMP thread count (and, under an MKL build, the",&
   "MKL pool as well), while --blas-threads writes the BLAS pool; where both",&
   "reach the same knob the flag that appears last on the command line wins.",&
   "",&
   "The gain falls with system size - about 49x at 24 atoms against about 2.8x",&
   "at 501 atoms - but OPENBLAS_NUM_THREADS=1 stays the fastest setting at both",&
   "scales measured here: at 501 atoms it measures 656 ms against 1827 ms with",&
   "the pool left at the thread count, while --blas-threads 1 with",&
   "OMP_WAIT_POLICY=PASSIVE measures 699 ms and --blas-threads 1 alone 946 ms.",&
   "MKL_NUM_THREADS and",&
   "OPENBLAS_DEFAULT_NUM_THREADS do not help: the first is ignored by a build",&
   "linked against OpenBLAS, the second measured a no-op here.",&
   "",&
   "Output Conventions:",&
   "",&
   "total energies are given in atomic units (Eh)",&
   "gaps/HL energies are given in eV",&
   "",&
   "More information can be obtained by `man 1 xtb` and `man 7 xcontrol`",&
   "or at https://xtb-docs.readthedocs.io/en/latest/contents.html",&
   ""
end subroutine help

subroutine help_legacy
   use, intrinsic :: iso_fortran_env, only : id => output_unit
   write(id,'(''Usage: xtb <geometry> [options]'',/)')

   write(id,'(''<geometry> may be provided as'','//&
   &    'x,''valid TM coordinate file (*coord in Bohr) or'','//&
   &    '/,''in xmol format (*xyz in Ångström).'',/)')

   write(id,'(''Options:'',/)')

   write(id,'(3x,''-c, --chrg <int>  '','// &
   &          'x,''Set charge to molecule'','//&
   &      '/,22x,''overrides charge in .CHRG file'')')

   write(id,'(3x,''-u, --uhf <int>   '','// &
   &          'x,''Number pf unpaired electrons or 2S'','//&
   &      '/,22x,''overrides setting in .UHF file'')')

   write(id,'(3x,''    --nox/--nodiff'','// &
   &          'x,''skip second, extended part in sTDA-xTB'')')

   write(id,'(3x,''    --pop         '','// &
   &          'x,''do population analysis'')')

   write(id,'(3x,''    --mowr <real> '','// &
   &          'x,''cut MO write above (default 3 Eh)'')')

   write(id,'(3x,''    --mold[en]    '','// &
   &          'x,''write formatted molden file'')')

   write(id,'(3x,''    --dip[ole]    '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --wbo         '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --lmo         '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --rdchrg      '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --md          '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --hessl       '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --optts       '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --ohessl      '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --mdopt       '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --path        '','// &
   &          'x,''deactivated feature'')')

   write(id,'(3x,''    --vip         '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --vea         '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --tm          '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --orca        '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --LS          '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --mopac       '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --qmdff       '','// &
   &          'x,''hidden feature'')')

   write(id,'(3x,''    --parx <file> '','// &
   &          'x,''read parameters for sTDA-xTB calculation'',' // &
   &      '/,22x,''(default: $XTBHOME/.param_stda2.xtb)'')')

   write(id,'(3x,''    --parv <file> '','// &
   &          'x,''read parameters for vTB part in sTDA-xTB'',' // &
   &      '/,22x,''(default: $XTBHOME/.param_stda1.xtb)'')')

   write(id,'(3x,''    --xtemp <real>'','// &
   &          'x,''electronic temperature for xTB (default 0 K)'')')

   write(id,'(3x,''    --etemp <real>'','// &
   &          'x,''electronic temperature for GFN (default 300 K)'')')

   write(id,'(3x,''    --fod         '','// &
   &          'x,''calculate the FOD and write molden.input file'','// &
   &      '/,22x,''with appropriate occupations for plotting'','// &
   &      '/,22x,''(defualt T = 12500 K)'')')

   write(id,'(3x,''    --gfn1        '','// &
   &          'x,''use GFN1-xTB parametrisation'')')

   write(id,'(3x,''    --gfn2        '','// &
   &          'x,''use GFN2-xTB parametrisation'')')

   write(id,'(3x,''    --gfn2d3      '','// &
   &          'x,''GFN2-xTB with D3 instead of D4 dispersion'')')

   write(id,'(3x,''    --scc         '','// &
   &          'x,''do single point only'')')

   write(id,'(3x,''    --grad        '','// &
   &          'x,''calculate GFNn-xTB gradient'')')

   write(id,'(3x,''    --acc <real>  '','// &
   &          'x,''GFNn-xTB accuracy (default 1.0)'')')

   write(id,'(3x,''    --opt [level] '','// &
   &          'x,''optimize at GFNn-xTB level, level can be one of'',' // &
   &      '/,22x,''crude, vloose, loose, tight, vtight, extreme'')')

   write(id,'(3x,''    --cycles <int> '','// &
   &          'x,''maximum number of optimization cycles'')')

   write(id,'(3x,''    --hess        '','// &
   &          'x,''compute Hessian at GFNn-xTB level'')')

   write(id,'(3x,''    --ohess       '','// &
   &          'x,''optimize and compute Hessian'')')

   write(id,'(3x,''    --omd         '','// &
   &          'x,''optimize and do MD'')')

   write(id,'(3x,''    --dipro <thr> '','// &
   &          'x,''calculate dipro coupling integrals'')')

   write(id,'(3x,''    --siman       '','// &
   &          'x,''conformational search'')')

   write(id,'(3x,''    --screen      '','// &
   &          'x,''opt. loop over ensemble'')')

   write(id,'(3x,''    --gmd         '','// &
   &          'x,''annealed MD for GMD procedure'')')

   write(id,'(3x,''    --modef       '','// &
   &          'x,''vibrational mode following'')')

   write(id,'(3x,''-g, --gbsa [solv] [state]'','// &
   &      '/,22x,''use GBSA implicit solvent for solvent [solv]'',' // &
   &      '/,22x,''and solvation state [state] = reference, bar1M'','// &
   &      '/,22x,''(default: bar1M)'')')

   write(id,'(3x,''    --help        '','// &
   &          'x,''show this message'')')

   write(id,'(/,''Useful Maschine Settings:'',/)')

   write(id,'(3x,''setenv MKL_NUM_THREADS <NCORE>'')')
   write(id,'(3x,''setenv OMP_STACKSIZE 500m'')')
   write(id,'(3x,''limit stacksize unlimited'')')

   write(id,'(/,''Output Conventions:'',/)')

   write(id,'(3x,''total energies are given in atomic units (Eh)'')')
   write(id,'(3x,''gaps/HL energies are given in eV'')')

   write(id,'(/,''Please read the manual carefully'',' // &
   &         'x,''(just kidding... there is no manual)'',/)')
end subroutine help_legacy

subroutine definebanner
   use, intrinsic :: iso_fortran_env, only : id => output_unit
   write(id,"(""           _"")")
   write(id,"(""          | |"")")
   write(id,"(""  _ __ ___| |_ _   _ _ __ _ __        __"")")
   write(id,"("" | '__/ _ \ __| | | | '__| '_ \      / _|"")")
   write(id,"("" | | |  __/ |_| |_| | |  | | | |___ | |_"")")
   write(id,"("" |_|  \___|\__|\__,_|_|  |_| |_/ _ \|  _|"")")
   write(id,"(""         _       __ _         | (_) | |"")")
   write(id,"(""        | |     / _(_)         \___/|_|"")")
   write(id,"(""      __| | ___| |_ _ _ __   ___"")")
   write(id,"(""     / _` |/ _ \  _| | '_ \ / _ \"")")
   write(id,"(""    | (_| |  __/ | | | | | |  __/"")")
   write(id,"(""     \__,_|\___|_| |_|_| |_|\___|"")")
end subroutine definebanner
