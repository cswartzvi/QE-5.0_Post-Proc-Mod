!
! Copyright (C) 2002-2011 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!


!=----------------------------------------------------------------------------=!
   SUBROUTINE printout_new_x   &
     ( nfi, tfirst, tfilei, tprint, tps, h, stress, tau0, vels, &
       fion, ekinc, temphc, tempp, temps, etot, enthal, econs, econt, &
       vnhh, xnhh0, vnhp, xnhp0, atot, ekin, epot, print_forces, print_stress, &
       tstdout)
!=----------------------------------------------------------------------------=!

      !
      USE kinds,             ONLY : DP
      USE control_flags,     ONLY : iprint, textfor, do_makov_payne
      USE energies,          ONLY : print_energies, dft_energy_type
      USE printout_base,     ONLY : printout_base_open, printout_base_close, &
                                    printout_pos, printout_cell, printout_stress
      USE constants,         ONLY : au_gpa, bohr_radius_cm, amu_au, &
                                    BOHR_RADIUS_ANGS, pi
      USE ions_base,         ONLY : na, nsp, nat, ind_bck, atm, ityp, amass, cdmi, &
                                    ions_cofmass, ions_displacement, label_srt
      USE cell_base,         ONLY : s_to_r, get_volume
      USE efield_module,     ONLY : tefield, pberryel, pberryion, &
                                    tefield2, pberryel2, pberryion2
      USE cg_module,         ONLY : tcg, itercg
      USE sic_module,        ONLY : self_interaction, sic_alpha, sic_epsilon
      USE electrons_module,  ONLY : print_eigenvalues
      USE pres_ai_mod,      ONLY : P_ext, Surf_t, volclu, surfclu, abivol, &
                                   abisur, pvar, n_ele
      USE xml_io_base,       ONLY : save_print_counter
      USE cp_main_variables, ONLY : nprint_nfi, iprint_stdout
      USE io_files,          ONLY : tmp_dir
      USE control_flags,     ONLY : ndw, tdipole
      USE polarization,      ONLY : print_dipole
      USE io_global,         ONLY : ionode, ionode_id, stdout
      USE control_flags,     ONLY : lwfpbe0, lwfpbe0nscf  ! Lingzhu Kong
      USE energies,          ONLY : exx  ! Lingzhu Kong
      !
      IMPLICIT NONE
      !
      INTEGER, INTENT(IN) :: nfi
      LOGICAL, INTENT(IN) :: tfirst, tfilei, tprint
      REAL(DP), INTENT(IN) :: tps
      REAL(DP), INTENT(IN) :: h( 3, 3 )
      REAL(DP), INTENT(IN) :: stress( 3, 3 )
      REAL(DP), INTENT(IN) :: tau0( :, : )  ! real positions
      REAL(DP), INTENT(IN) :: vels( :, : )  ! scaled velocities
      REAL(DP), INTENT(IN) :: fion( :, : )  ! real forces
      REAL(DP), INTENT(IN) :: ekinc, temphc, tempp, etot, enthal, econs, econt
      REAL(DP), INTENT(IN) :: temps( : ) ! partial temperature for different ionic species
      REAL(DP), INTENT(IN) :: vnhh( 3, 3 ), xnhh0( 3, 3 ), vnhp( 1 ), xnhp0( 1 )
      REAL(DP), INTENT(IN) :: atot! enthalpy of system for c.g. case
      REAL(DP), INTENT(IN) :: ekin
      REAL(DP), INTENT(IN) :: epot ! ( epseu + eht + exc )
      LOGICAL, INTENT(IN) :: print_forces, print_stress, tstdout
   
   !
      REAL(DP) :: stress_gpa( 3, 3 )
      REAL(DP) :: cdm0( 3 )
      REAL(DP) :: dis( nsp )
      REAL(DP) :: out_press, volume
      REAL(DP) :: totalmass
      INTEGER  :: isa, is, ia, kilobytes
      REAL(DP), ALLOCATABLE :: tauw(:, :)
      LOGICAL  :: tsic, tfile
      LOGICAL, PARAMETER :: nice_output_files=.false.
      !
      ! avoid double printing to files by refering to nprint_nfi
      !
      tfile = tfilei .and. ( nfi .gt. nprint_nfi )
      !
     
      !
      CALL memstat( kilobytes )
      !
      IF( ionode .AND. tfile .AND. tprint ) THEN
         CALL printout_base_open()
      END IF
      !
      IF( tprint ) THEN
         IF ( tfile ) THEN
            ! we're writing files, let's save nfi
            CALL save_print_counter( nfi, tmp_dir, ndw )
         ELSE IF ( tfilei ) then
            ! not there yet, save the old nprint_nfi
            CALL save_print_counter( nprint_nfi, tmp_dir, ndw )
         END IF
      END IF
      !
      volume = get_volume( h )
      !
      stress_gpa = stress * au_gpa
      !
      out_press = ( stress_gpa(1,1) + stress_gpa(2,2) + stress_gpa(3,3) ) / 3.0d0
      !
      IF( nfi > 0 ) THEN
         CALL update_accomulators &
              ( ekinc, ekin, epot, etot, tempp, enthal, econs, out_press, volume )
      END IF
      !
      ! Makov-Payne correction to the total energy (isolated systems only)
      IF( do_makov_payne .AND. tprint ) CALL makov_payne( etot )
      !
      !
      IF( ionode ) THEN
         !
         IF( tprint ) THEN
            !
            tsic = ( self_interaction /= 0 )
            !
            IF(tstdout) &
               CALL print_energies( tsic, sic_alpha = sic_alpha, sic_epsilon = sic_epsilon, textfor = textfor )
            !
            CALL print_eigenvalues( 31, tfile, tstdout, nfi, tps )
            !
            IF(tstdout) WRITE( stdout, * )
            !
            IF( kilobytes > 0 .AND. tstdout ) &
               WRITE( stdout, fmt="(3X,'Allocated memory (kb) = ', I9 )" ) kilobytes
            !
            IF(tstdout) WRITE( stdout, * )
            !
            IF( tdipole ) CALL print_dipole( 32, tfile, nfi, tps )
            !
            IF(tstdout) CALL printout_cell( stdout, h )
            !
            IF( tfile ) CALL printout_cell( 36, h, nfi, tps )
            !
            !  System density:
            !
            totalmass = 0.0d0
            DO is = 1, nsp
              totalmass = totalmass + amass(is) * na(is)
            END DO
            totalmass = totalmass / volume * 11.2061d0 ! AMU_SI * 1000.0 / BOHR_RADIUS_CM**3 
            IF(tstdout) &
               WRITE( stdout, fmt='(/,3X,"System Density [g/cm^3] : ",F10.4,/)' ) totalmass
            !
            ! Compute Center of mass displacement since the initialization of step counter
            !
            CALL ions_cofmass( tau0, amass, na, nsp, cdm0 )
            !
            IF(tstdout) &
               WRITE( stdout,1000) SUM( ( cdm0(:)-cdmi(:) )**2 ) 
            !
            CALL ions_displacement( dis, tau0 )
            !
            IF( print_stress ) THEN
               !
               IF(tstdout) &
                  CALL printout_stress( stdout, stress_gpa )
               !
               IF( tfile ) CALL printout_stress( 38, stress_gpa, nfi, tps )
               !
            END IF
            !
            ! ... write out a standard XYZ file in angstroms
            !
            IF(tstdout) &
               CALL printout_pos( stdout, tau0, nat, what = 'pos', &
                                  label = label_srt, sort = ind_bck )
            !
            IF( tfile ) then
               if (.not.nice_output_files) then
                  CALL printout_pos( 35, tau0, nat, nfi = nfi, tps = tps )
               else
                  CALL printout_pos( 35, tau0, nat, what = 'xyz', &
                               nfi = nfi, tps = tps, label = label_srt, &
                               fact= BOHR_RADIUS_ANGS ,sort = ind_bck )
               endif
            END IF
            !
            ALLOCATE( tauw( 3, nat ) )
            !
            isa = 0
            !
            DO is = 1, nsp
               !
               DO ia = 1, na(is)
                  !
                  isa = isa + 1
                  !
                  CALL s_to_r( vels(:,isa), tauw(:,isa), h )
                  !
               END DO
               !
            END DO
            !
            IF(tstdout) WRITE( stdout, * )
            !
            IF(tstdout) &
               CALL printout_pos( stdout, tauw, nat, &
                               what = 'vel', label = label_srt, sort = ind_bck )
            !
            IF( tfile ) then
               if (.not.nice_output_files) then
                  CALL printout_pos( 34, tauw, nat, nfi = nfi, tps = tps )
               else
                  CALL printout_pos( 34, tauw, nat, nfi = nfi, tps = tps, &
                               what = 'vel', label = label_srt, sort = ind_bck )
               endif
            END IF
            !
            IF( print_forces ) THEN
               !
               IF(tstdout) WRITE( stdout, * )
               !
               IF(tstdout) &
                  CALL printout_pos( stdout, fion, nat, &
                                  what = 'for', label = label_srt, sort = ind_bck )
               !
               IF( tfile ) then
                  if (.not.nice_output_files) then
                     CALL printout_pos( 37, fion, nat, nfi = nfi, tps = tps )
                  else
                     CALL printout_pos( 37, fion, nat, nfi = nfi, tps = tps, &
                          what = 'for', label = label_srt, sort = ind_bck )
                  endif
               END IF
               !
            END IF
            !
            DEALLOCATE( tauw )
            !
            ! ...       Write partial temperature and MSD for each atomic specie tu stdout
            !
            IF(tstdout) WRITE( stdout, * ) 
            IF(tstdout) WRITE( stdout, 1944 )
            !
            DO is = 1, nsp
               IF( tstdout ) WRITE( stdout, 1945 ) is, temps(is), dis(is)
            END DO
            !
            IF( tfile ) WRITE( 33, 2948 ) nfi, ekinc, temphc, tempp, etot, enthal, &
                                          econs, econt, volume, out_press, tps
            IF( tfile ) WRITE( 39, 2949 ) nfi, vnhh(3,3), xnhh0(3,3), vnhp(1), &
                                          xnhp0(1), tps
            !
         END IF
         !
       END IF
      !

       IF( ionode .AND. tfile .AND. tprint ) THEN
         !
         ! ... Close and flush unit 30, ... 40
         !
         CALL printout_base_close()
         !
      END IF
      !
      IF( ( MOD( nfi, iprint_stdout ) == 0 ) .OR. tfirst )  THEN
         !
         WRITE( stdout, * )
!======================================================
!Lingzhu Kong
         IF(lwfpbe0 .or. lwfpbe0nscf)THEN
           WRITE( stdout, 19470 )
         ELSE
          WRITE( stdout, 1947)
         END IF
!======================================================
         IF ( abivol .AND. pvar ) write(stdout,*) 'P = ', P_ext*au_gpa
         !
      END IF
      ! 
      if (abivol) then
         write(stdout,*) nfi, 'ab-initio volume = ', volclu, ' a.u.^3'
         write(stdout,*) nfi, 'PV = ', P_ext*volclu, ' ha'
      end if
      if (abisur) then
         write(stdout,*) nfi, 'ab-initio surface = ', surfclu, ' a.u.^2'
         if (abivol) write(stdout,*) nfi, 'spherical surface = ', &
                 4.d0*pi*(0.75d0*volclu/pi)**(2.d0/3.d0), ' a.u.^2'
         write(stdout,*) nfi, 't*S = ', Surf_t*surfclu, ' ha'
      end if
      if (abivol.or.abisur) write(stdout,*) nfi, &
         ' # of electrons within the isosurface = ', n_ele

      IF( .not. tcg ) THEN
         !
!===================================================================
!Lingzhu Kong
         IF( lwfpbe0 .or. lwfpbe0nscf ) THEN
            WRITE( stdout, 19480 ) nfi, ekinc, temphc, tempp, -exx*0.25, &
                                  etot-exx*0.25, enthal, econs, econt,   &
                                  vnhh(3,3), xnhh0(3,3), vnhp(1),  xnhp0(1)
         ELSE
            WRITE( stdout, 1948 ) nfi, ekinc, temphc, tempp, etot, enthal, &
                      econs, econt, vnhh(3,3), xnhh0(3,3), vnhp(1),  xnhp0(1)
         END IF
!===================================================================
      ELSE
         IF ( MOD( nfi, iprint ) == 0 .OR. tfirst ) THEN
            !
            WRITE( stdout, * )
            WRITE( stdout, 255 ) 'nfi','tempp','E','-T.S-mu.nbsp','+K_p','#Iter'
            !
         END IF
         !
         WRITE( stdout, 256 ) nfi, INT( tempp ), etot, atot, econs, itercg
         !
      END IF

      IF( tefield) THEN
         IF(ionode) write(stdout,'( A14,F12.6,2X,A14,F12.6)') 'Elct. dipole 1',-pberryel,'Ionic dipole 1',-pberryion
      ENDIF
      IF( tefield2) THEN
         IF(ionode) write(stdout,'( A14,F12.6,2X,A14,F12.6)') 'Elct. dipole 2',-pberryel2,'Ionic dipole 2',-pberryion2
      ENDIF
      !
      !
255   FORMAT( '     ',A5,A8,3(1X,A12),A6 )
256   FORMAT( 'Step ',I5,1X,I7,1X,F12.5,1X,F12.5,1X,F12.5,1X,I5 )
1000  FORMAT(/,3X,'Center of mass square displacement (a.u.): ',F10.6,/)
1944  FORMAT(//'   Partial temperatures (for each ionic specie) ', &
             /,'   Species  Temp (K)   Mean Square Displacement (a.u.)')
1945  FORMAT(3X,I6,1X,F10.2,1X,F10.4)
1947  FORMAT( 2X,'nfi',4X,'ekinc',2X,'temph',2X,'tempp',8X,'etot',6X,'enthal', &
           & 7X,'econs',7X,'econt',4X,'vnhh',3X,'xnhh0',4X,'vnhp',3X,'xnhp0' )
1948  FORMAT( I5,1X,F8.5,1X,F6.1,1X,F6.1,4(1X,F11.5),4(1X,F7.4) )
!===============================================================================
!Lingzhu Kong
19470 FORMAT( 2X,'nfi',4X,'ekinc',2X,'temph',2X,'tempp',8X,'exx', 8X,'etot', &
              6X,'enthal',7X,'econs',7X,'econt',4X,'vnhh',3X,'xnhh0',4X, &
              'vnhp',3X,'xnhp0')
19480  FORMAT( I6,1X,F8.5,1X,F6.1,1X,F6.1,5(1X,F11.5),4(1X,F7.4) )
!===============================================================================
2948  FORMAT( I6,1X,F8.5,1X,F6.1,1X,F6.1,4(1X,F11.5),F10.2, F8.2, F8.5 )
2949  FORMAT( I6,1X,4(1X,F7.4), F8.5 )
      !
      RETURN
   END SUBROUTINE printout_new_x
   !  
   !
!=----------------------------------------------------------------------------=!
  SUBROUTINE print_legend()
!=----------------------------------------------------------------------------=!
    !
    USE io_global, ONLY : ionode, stdout
    !
    IMPLICIT NONE
    !
    IF ( .NOT. ionode ) RETURN
    !
    WRITE( stdout, *) 
    WRITE( stdout, *) '  Short Legend and Physical Units in the Output'
    WRITE( stdout, *) '  ---------------------------------------------'
    WRITE( stdout, *) '  NFI    [int]          - step index'
    WRITE( stdout, *) '  EKINC  [HARTREE A.U.] - kinetic energy of the fictitious electronic dynamics'
    WRITE( stdout, *) '  TEMPH  [K]            - Temperature of the fictitious cell dynamics'
    WRITE( stdout, *) '  TEMP   [K]            - Ionic temperature'
    WRITE( stdout, *) '  ETOT   [HARTREE A.U.] - Scf total energy (Kohn-Sham hamiltonian)'
    WRITE( stdout, *) '  ENTHAL [HARTREE A.U.] - Enthalpy ( ETOT + P * V )'
    WRITE( stdout, *) '  ECONS  [HARTREE A.U.] - Enthalpy + kinetic energy of ions and cell'
    WRITE( stdout, *) '  ECONT  [HARTREE A.U.] - Constant of motion for the CP lagrangian'
    WRITE( stdout, *) 
    !
    RETURN
    !
  END SUBROUTINE print_legend



!=----------------------------------------------------------------------------=!
   SUBROUTINE printacc( )
!=----------------------------------------------------------------------------=!

      USE kinds,               ONLY : DP
      USE cp_main_variables,   ONLY : acc, acc_this_run, nfi, nfi_run
      USE io_global,           ONLY : ionode, stdout

      IMPLICIT NONE
      !
      REAL(DP) :: avgs(9)
      REAL(DP) :: avgs_run(9)
 
      avgs     = 0.0d0
      avgs_run = 0.0d0
      !
      IF ( nfi > 0 ) THEN
         avgs  = acc( 1:9 ) / DBLE( nfi )
      END IF
      !
      IF ( nfi_run > 0 ) THEN
         avgs_run = acc_this_run(1:9) / DBLE( nfi_run )
      END IF

      IF( ionode ) THEN
        WRITE( stdout,1949)
        WRITE( stdout,1951) avgs(1), avgs_run(1)
        WRITE( stdout,1952) avgs(2), avgs_run(2)
        WRITE( stdout,1953) avgs(3), avgs_run(3)
        WRITE( stdout,1954) avgs(4), avgs_run(4)
        WRITE( stdout,1955) avgs(5), avgs_run(5)
        WRITE( stdout,1956) avgs(6), avgs_run(6)
        WRITE( stdout,1957) avgs(7), avgs_run(7)
        WRITE( stdout,1958) avgs(8), avgs_run(8)
        WRITE( stdout,1959) avgs(9), avgs_run(9)
        WRITE( stdout,1990)
 1949   FORMAT(//,3X,'Averaged Physical Quantities',/ &
              ,3X,'                  ',' accomulated','      this run')
 1951   FORMAT(3X,'ekinc         : ',F14.5,F14.5,' (AU)')
 1952   FORMAT(3X,'ekin          : ',F14.5,F14.5,' (AU)')
 1953   FORMAT(3X,'epot          : ',F14.5,F14.5,' (AU)')
 1954   FORMAT(3X,'total energy  : ',F14.5,F14.5,' (AU)')
 1955   FORMAT(3X,'temperature   : ',F14.5,F14.5,' (K )')
 1956   FORMAT(3X,'enthalpy      : ',F14.5,F14.5,' (AU)')
 1957   FORMAT(3X,'econs         : ',F14.5,F14.5,' (AU)')
 1958   FORMAT(3X,'pressure      : ',F14.5,F14.5,' (Gpa)')
 1959   FORMAT(3X,'volume        : ',F14.5,F14.5,' (AU)')
 1990   FORMAT(/)
      END IF

      RETURN
    END SUBROUTINE printacc



!=----------------------------------------------------------------------------=!
    SUBROUTINE open_and_append_x( iunit, file_name )
!=----------------------------------------------------------------------------=!
      USE io_global, ONLY: ionode
      IMPLICIT NONE
      INTEGER, INTENT(IN) :: iunit
      CHARACTER(LEN = *), INTENT(IN) :: file_name
      INTEGER :: ierr
      IF( ionode ) THEN
        OPEN( UNIT = iunit, FILE = trim( file_name ), &
          STATUS = 'unknown', POSITION = 'append', IOSTAT = ierr)
        IF( ierr /= 0 ) &
          CALL errore( ' open_and_append ', ' opening file '//trim(file_name), 1 )
      END IF
      RETURN
    END SUBROUTINE open_and_append_x

!=----------------------------------------------------------------------------=!
   SUBROUTINE update_accomulators &
      ( ekinc, ekin, epot, etot, tempp, enthal, econs, press, volume )
!=----------------------------------------------------------------------------=!

      USE kinds,               ONLY : DP
      USE cp_main_variables,   ONLY : acc, acc_this_run, nfi_run

      IMPLICIT NONE

      REAL(DP), INTENT(IN) :: ekinc, ekin, epot, etot, tempp
      REAL(DP), INTENT(IN) :: enthal, econs, press, volume

      nfi_run = nfi_run + 1

      ! ...   sum up values to be averaged

      acc(1) = acc(1) + ekinc
      acc(2) = acc(2) + ekin
      acc(3) = acc(3) + epot
      acc(4) = acc(4) + etot
      acc(5) = acc(5) + tempp
      acc(6) = acc(6) + enthal
      acc(7) = acc(7) + econs
      acc(8) = acc(8) + press  ! pressure in GPa
      acc(9) = acc(9) + volume

      ! ...   sum up values to be averaged

      acc_this_run(1) = acc_this_run(1) + ekinc
      acc_this_run(2) = acc_this_run(2) + ekin
      acc_this_run(3) = acc_this_run(3) + epot
      acc_this_run(4) = acc_this_run(4) + etot
      acc_this_run(5) = acc_this_run(5) + tempp
      acc_this_run(6) = acc_this_run(6) + enthal
      acc_this_run(7) = acc_this_run(7) + econs
      acc_this_run(8) = acc_this_run(8) + press  ! pressure in GPa
      acc_this_run(9) = acc_this_run(9) + volume

      RETURN
   END SUBROUTINE
