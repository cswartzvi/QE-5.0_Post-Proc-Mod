!
! Copyright (C) 2002-2010 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!

!=----------------------------------------------------------------------=!
!
!   CP90 / FPMD common init subroutine 
!
!=----------------------------------------------------------------------=!


  subroutine init_dimensions(  )

      !
      !     initialize G-vectors and related quantities
      !

      USE kinds,                ONLY: dp
      USE constants,            ONLY: tpi
      use io_global,            only: stdout, ionode
      use control_flags,        only: gamma_only, iverbosity
      use cell_base,            only: ainv, at, omega, alat
      use small_box,            only: small_box_set
      use smallbox_grid_dim,    only: smallbox_grid_init,smallbox_grid_info
      USE grid_subroutines,     ONLY: realspace_grids_init, realspace_grids_info
      use ions_base,            only: nat
      USE recvec_subs,          ONLY: ggen
      USE gvect,                ONLY: mill_g, eigts1,eigts2,eigts3, gg, &
                                      ecutrho, gcutm, gvect_init
      use gvecs,                only: gcutms, gvecs_init
      use gvecw,                only: gkcut, gvecw_init, g2kin_init
      USE smallbox_subs,        ONLY: ggenb
      USE fft_base,             ONLY: dfftp, dffts, dfftb
      USE fft_scalar,           ONLY: cft_b_omp_init
      USE stick_set,            ONLY: pstickset
      USE control_flags,        ONLY: tdipole, gamma_only
      USE berry_phase,          ONLY: berry_setup
      USE electrons_module,     ONLY: bmeshset
      USE electrons_base,       ONLY: distribute_bands
      USE problem_size,         ONLY: cpsizes
      USE mp_global,            ONLY: me_bgrp, root_bgrp, nproc_bgrp, nbgrp, my_bgrp_id, intra_bgrp_comm
      USE mp_global,            ONLY: get_ntask_groups
      USE uspp,                 ONLY: okvan, nlcc_any

      implicit none
! 
      integer  :: i
      real(dp) :: rat1, rat2, rat3
      real(dp) :: bg(3,3), tpiba2 
      integer :: ng_, ngs_, ngm_ , ngw_ , nogrp_


      tpiba2 = ( tpi / alat ) ** 2
      IF( ionode ) THEN
        WRITE( stdout, 100 )
 100    FORMAT( //, &
                3X,'Simulation dimensions initialization',/, &
                3X,'------------------------------------' )
      END IF
      !
      ! ... Initialize bands indexes for parallel linear algebra 
      ! ... (distribute bands to processors)
      !
      CALL bmeshset( )
      !
      ! ... cell dimensions and lattice vectors
      ! ... note that at are in alat units

      call recips( at(1,1), at(1,2), at(1,3), bg(1,1), bg(1,2), bg(1,3) )

      !     bg(:,1), bg(:,2), bg(:,3) are the basis vectors, in
      !     2pi/alat units, generating the reciprocal lattice

      ! ... Initialize FFT real-space grids and small box grid
      !
      CALL realspace_grids_init( dfftp, dffts, at, bg, gcutm, gcutms)
      CALL smallbox_grid_init( dfftp, dfftb )

      IF( ionode ) THEN

        WRITE( stdout,210) 
210     format(/,3X,'unit vectors of full simulation cell',&
              &/,3X,'in real space:',25x,'in reciprocal space (units 2pi/alat):')
        WRITE( stdout,'(3X,I1,1X,3f10.4,10x,3f10.4)') 1,at(:,1)*alat,bg(:,1)
        WRITE( stdout,'(3X,I1,1X,3f10.4,10x,3f10.4)') 2,at(:,2)*alat,bg(:,2)
        WRITE( stdout,'(3X,I1,1X,3f10.4,10x,3f10.4)') 3,at(:,3)*alat,bg(:,3)

      END IF
      !
      do i=1,3
         ainv(1,i)=bg(i,1)/alat
         ainv(2,i)=bg(i,2)/alat
         ainv(3,i)=bg(i,3)/alat
      end do

      !
      ! ainv  is transformation matrix from cartesian to crystal coordinates
      !       if r=x1*a1+x2*a2+x3*a3 => x(i)=sum_j ainv(i,j)r(j)
      !       Note that ainv is really the inverse of a=(a1,a2,a3)
      !       (but only if the axis triplet is right-handed, otherwise
      !        for a left-handed triplet, ainv is minus the inverse of a)
      !

      ! ... set the sticks mesh and distribute g vectors among processors
      ! ... pstickset lso sets the local real-space grid dimensions
      !
      nogrp_ = get_ntask_groups()

      CALL pstickset( gamma_only, bg, gcutm, gkcut, gcutms, &
        dfftp, dffts, ngw_ , ngm_ , ngs_ , me_bgrp, root_bgrp, nproc_bgrp, intra_bgrp_comm, nogrp_ )
      !
      !
      ! ... Initialize reciprocal space local and global dimensions
      !     NOTE in a parallel run ngm_ , ngw_ , ngs_ here are the 
      !     local number of reciprocal vectors
      !
      CALL gvect_init ( ngm_ , intra_bgrp_comm )
      CALL gvecs_init ( ngs_ , intra_bgrp_comm )
      !
      ! ... Print real-space grid dimensions
      !
      CALL realspace_grids_info ( dfftp, dffts, nproc_bgrp )
      CALL smallbox_grid_info ( dfftb )
      !
      ! ... generate g-space vectors (dense and smooth grid)
      !
#ifdef __LOWMEM
      CALL ggen( gamma_only, at, bg, intra_bgrp_comm )
#else
      CALL ggen( gamma_only, at, bg )
#endif
      !
      ! ... allocate and generate (modified) kinetic energy
      !
      CALL gvecw_init ( ngw_ , intra_bgrp_comm )
      CALL g2kin_init ( gg, tpiba2 )
      ! 
      !  Allocate index required to compute polarizability
      !
      IF( tdipole ) THEN
        CALL berry_setup( ngw_ , mill_g )
      END IF
      !
      !     global arrays are no more needed
      !
      if( allocated( mill_g ) ) deallocate( mill_g )
      !
      !     allocate spaces for phases e^{-iG*tau_s}
      !
      allocate( eigts1(-dfftp%nr1:dfftp%nr1,nat) )
      allocate( eigts2(-dfftp%nr2:dfftp%nr2,nat) )
      allocate( eigts3(-dfftp%nr3:dfftp%nr3,nat) )
      !
      !     small boxes
      !
      IF ( dfftb%nr1 > 0 .AND. dfftb%nr2 > 0 .AND. dfftb%nr3 > 0 ) THEN

         !  set the small box parameters

         rat1 = DBLE( dfftb%nr1 ) / DBLE( dfftp%nr1 )
         rat2 = DBLE( dfftb%nr2 ) / DBLE( dfftp%nr2 )
         rat3 = DBLE( dfftb%nr3 ) / DBLE( dfftp%nr3 )
         !
         CALL small_box_set( alat, omega, at, rat1, rat2, rat3, tprint = .TRUE. )
         !
         !  generate small-box G-vectors, initialize FFT tables
         !
         CALL ggenb ( ecutrho, iverbosity )
         !
#if defined __OPENMP && defined __FFTW 
         CALL cft_b_omp_init( dfftb%nr1, dfftb%nr2, dfftb%nr3 )
#endif
      ELSE IF( okvan .OR. nlcc_any ) THEN

         CALL errore( ' init_dimensions ', ' nr1b, nr2b, nr3b must be given for ultrasoft and core corrected pp ', 1 )

      END IF

      ! ... distribute bands

      CALL distribute_bands( nbgrp, my_bgrp_id )

      ! ... printout g vector distribution summary
      !
      CALL gmeshinfo()
      !
      !  CALL cpsizes( )  Maybe useful 
      !
      !   Flush stdout
      !
      CALL flush_unit( stdout )
      !
      return
      end subroutine init_dimensions




!-----------------------------------------------------------------------
      subroutine init_geometry ( )
!-----------------------------------------------------------------------
!
      USE kinds,            ONLY: DP
      use control_flags,    only: iprint, thdyn, ndr, nbeg, tbeg
      use io_global,        only: stdout, ionode
      use mp_global,        only: nproc_bgrp, me_bgrp, intra_bgrp_comm, root_bgrp
      USE io_files,         ONLY: tmp_dir     
      use ions_base,        only: na, nsp, nat, tau_srt, ind_srt, if_pos, atm,&
                                  amass
      use cell_base,        only: at, alat, r_to_s, cell_init, deth

      use cell_base,        only: ibrav, ainv, h, hold, tcell_base_init
      USE ions_positions,   ONLY: allocate_ions_positions, atoms_init, &
                                  atoms0, atomsm, atomsp
      use cp_restart,       only: cp_read_cell
      USE fft_base,         ONLY: dfftb
      USE fft_types,        ONLY: fft_box_allocate
      USE cp_main_variables,ONLY: ht0, htm, taub
      USE atoms_type_module,ONLY: atoms_type
      USE cp_interfaces,    ONLY: newinit
      USE constants,        ONLY: amu_au

      implicit none
      !
      ! local
      !
      integer :: i, j
      real(DP) :: gvel(3,3), ht(3,3)
      real(DP) :: xnhh0(3,3), xnhhm(3,3), vnhh(3,3), velh(3,3)
      REAL(DP), ALLOCATABLE :: pmass(:), taus_srt( :, : )

      IF( .NOT. tcell_base_init ) &
         CALL errore( ' init_geometry ', ' cell_base_init has not been call yet! ', 1 )

      IF( ionode ) THEN
        WRITE( stdout, 100 )
 100    FORMAT( //, &
                3X,'System geometry initialization',/, &
                3X,'------------------------------' )
      END IF

      ! Set ht0 and htm, cell at time t and t-dt
      !
      CALL cell_init( alat, at, ht0 )
      CALL cell_init( alat, at, htm )

      CALL allocate_ions_positions( nsp, nat )
      ! 
      ! Scale positions that have been read from standard input 
      ! according to the cell given in the standard input too
      ! taus_srt = scaled, tau_srt = atomic units
      !
      ALLOCATE( taus_srt( 3, nat ), pmass(nsp) )
      
      CALL r_to_s( tau_srt, taus_srt, na, nsp, ainv )

      pmass (:) = amass(1:nsp) * amu_au
      CALL atoms_init( atomsm, atoms0, atomsp, taus_srt, ind_srt, if_pos, atm, ht0%hmat, nat, nsp, na, pmass )
      !
      DEALLOCATE( pmass, taus_srt )
      !
      !  Allocate box descriptor
      !
      ALLOCATE( taub( 3, nat ) )
      !
      CALL fft_box_allocate( dfftb, me_bgrp, root_bgrp, nproc_bgrp, intra_bgrp_comm, nat )
      !
      !  if tbeg = .true.  the geometry is given in the standard input even if
      !  we are restarting a previous run
      !
      if( ( nbeg > -1 ) .and. ( .not. tbeg ) ) then
        !
        ! read only h and hold from restart file "ndr"
        !
        CALL cp_read_cell( ndr, tmp_dir, .TRUE., ht, hold, velh, gvel, xnhh0, xnhhm, vnhh )

        CALL cell_init( 't', ht0, ht   )
        CALL cell_init( 't', htm, hold )
        ht0%hvel = velh  !  set cell velocity
        ht0%gvel = gvel 

        h     = TRANSPOSE( ht   )
        ht    = TRANSPOSE( hold )
        hold  = ht
        ht    = TRANSPOSE( velh )
        velh  = ht

        WRITE( stdout,344) ibrav
        do i=1,3
          WRITE( stdout,345) (h(i,j),j=1,3)
        enddo
        WRITE( stdout,*)


      else
        !
        ! geometry is set to the cell parameters read from stdin
        !
        do i = 1, 3
            h(i,1) = at(i,1)*alat
            h(i,2) = at(i,2)*alat
            h(i,3) = at(i,3)*alat
        enddo

        hold = h

      end if
      !
      !   generate true g-space
      !
      call newinit( ht0%hmat, iverbosity = 2 )
      !
      CALL invmat( 3, h, ainv, deth )
      !
 344  format(3X,'ibrav = ',i4,'       cell parameters ',/)
 345  format(3(4x,f10.5))
      return
      end subroutine init_geometry



!-----------------------------------------------------------------------

    subroutine newinit_x( h, iverbosity )
      !
      !     re-initialization of lattice parameters and g-space vectors.
      !     Note that direct and reciprocal lattice primitive vectors
      !     at, ainv, and corresponding quantities for small boxes
      !     are recalculated according to the value of cell parameter h
      !
      USE kinds,                 ONLY : DP
      USE constants,             ONLY : tpi
      USE cell_base,             ONLY : at, bg, omega, alat, tpiba2, &
                                        cell_base_reinit
      USE gvecw,                 ONLY : g2kin_init
      USE gvect,                 ONLY : g, gg, ngm, mill
      USE fft_base,              ONLY : dfftp, dfftb
      USE small_box,             ONLY : small_box_set
      USE smallbox_subs,         ONLY : gcalb
      USE io_global,             ONLY : stdout, ionode
      !
      implicit none
      !
      REAL(DP), INTENT(IN) :: h(3,3)
      INTEGER,  INTENT(IN) :: iverbosity
      !
      REAL(DP) :: rat1, rat2, rat3
      INTEGER :: ig, i1, i2, i3
      !
      !WRITE( stdout, "(4x,'h from newinit')" )
      !do i=1,3
      !   WRITE( stdout, '(3(4x,f12.7)' ) (h(i,j),j=1,3)
      !enddo
      !
      !  re-initialize the cell base module with the new geometry
      !
      CALL cell_base_reinit( TRANSPOSE( h ) )
      !
      !  re-calculate G-vectors and kinetic energy
      !
      do ig=1,ngm
         i1=mill(1,ig)
         i2=mill(2,ig)
         i3=mill(3,ig)
         g(:,ig)=i1*bg(:,1)+i2*bg(:,2)+i3*bg(:,3)
         gg(ig)=g(1,ig)**2 + g(2,ig)**2 + g(3,ig)**2
      enddo
      !
      call g2kin_init ( gg, tpiba2 )
      !
      IF ( dfftb%nr1 == 0 .OR. dfftb%nr2 == 0 .OR. dfftb%nr3 == 0 ) RETURN
      !
      !   generation of little box g-vectors
      !
      rat1 = DBLE( dfftb%nr1 ) / DBLE( dfftp%nr1 )
      rat2 = DBLE( dfftb%nr2 ) / DBLE( dfftp%nr2 )
      rat3 = DBLE( dfftb%nr3 ) / DBLE( dfftp%nr3 )
      CALL small_box_set( alat, omega, at, rat1, rat2, rat3, tprint = ( iverbosity > 1 ) )
      !
      call gcalb ( )
      !
      return
    end subroutine newinit_x
