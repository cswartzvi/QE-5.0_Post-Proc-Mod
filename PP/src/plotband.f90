!
! Copyright (C) 2001-2007 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
PROGRAM plotband

  IMPLICIT NONE
  INTEGER, PARAMETER :: stdout=6
  real, ALLOCATABLE :: e(:,:), k(:,:), e_in(:), kx(:)
  real :: k1(3), k2(3), ps
  real, ALLOCATABLE :: e_rap(:,:), k_rap(:,:)
  INTEGER, ALLOCATABLE :: nbnd_rapk(:), rap(:,:)
  INTEGER, ALLOCATABLE :: npoints(:)
  INTEGER :: nks = 0, nbnd = 0, ios, nlines, n,i,j,ni,nf,nl
  INTEGER :: nks_rap = 0, nbnd_rap = 0
  LOGICAL, ALLOCATABLE :: high_symmetry(:), is_in_range(:), is_in_range_rap(:)
  CHARACTER(len=256) :: filename, filename1
  NAMELIST /plot/ nks, nbnd
  NAMELIST /plot_rap/ nks_rap, nbnd_rap
  INTEGER :: n_interp
  real, ALLOCATABLE :: k_interp(:), e_interp(:), coef_interp(:,:)

  real :: emin = 1.e10, emax =-1.e10, etic, eref, deltaE, Ef

  INTEGER, PARAMETER :: max_lines=99
  real :: mine
  INTEGER :: point(max_lines+1), nrap(max_lines)
  INTEGER :: ilines, irap, ibnd, ipoint, jnow

  real, PARAMETER :: cm=28.453, xdim=15.0*cm, ydim=10.0*cm, &
                     x0=2.0*cm, y0=2.0*cm, eps=1.e-4

  LOGICAL :: exist_rap
  LOGICAL, ALLOCATABLE :: todo(:,:)


  CALL get_file ( filename )
  OPEN(unit=1,file=filename,form='formatted')
  READ (1, plot, iostat=ios)
  !
  IF (nks <= 0 .or. nbnd <= 0 .or. ios /= 0) THEN
     STOP 'Error reading file header'
  ELSE
     PRINT '("Reading ",i4," bands at ",i6," k-points")', nbnd, nks
  ENDIF

  filename1=trim(filename)//".rap"
  exist_rap=.true.
  OPEN(unit=21,file=filename1,form='formatted',status='old',err=100,iostat=ios)

100 IF (ios /= 0) THEN
     exist_rap=.false.
  ENDIF
  IF (exist_rap) THEN
     READ (21, plot_rap, iostat=ios)
     IF (nks_rap/=nks.or.nbnd_rap/=nbnd.or.ios/=0) THEN
        WRITE(6,'("file with representations not compatible with bands")')
        exist_rap=.false.
     ENDIF
  ENDIF
  !
  ALLOCATE (e(nbnd,nks))
  ALLOCATE (k(3,nks), e_in(nks), kx(nks), npoints(nks), high_symmetry(nks))
  ALLOCATE (is_in_range(nbnd))

  IF (exist_rap) THEN
     ALLOCATE(nbnd_rapk(nks))
     ALLOCATE(e_rap(nbnd,nks))
     ALLOCATE(rap(nbnd,nks))
     ALLOCATE(k_rap(3,nks))
     ALLOCATE(todo(nbnd,2))
     ALLOCATE (is_in_range_rap(nbnd))
  ENDIF

  high_symmetry=.false.

  DO n=1,nks
     READ(1,*,end=20,err=20) ( k(i,n), i=1,3 )
     READ(1,*,end=20,err=20) (e(i,n),i=1,nbnd)
     IF (exist_rap) THEN
        READ(21,*,end=20,err=20) (k_rap(i,n),i=1,3), high_symmetry(n)
        READ(21,*,end=20,err=20) (rap(i,n),i=1,nbnd)
        IF (abs(k(1,n)-k_rap(1,n))+abs(k(2,n)-k_rap(2,n))+  &
            abs(k(3,n)-k_rap(3,n))  > eps ) THEN
            WRITE(stdout,'("Incompatible k points in rap file")')
            DEALLOCATE(nbnd_rapk)
            DEALLOCATE(e_rap)
            DEALLOCATE(rap)
            DEALLOCATE(k_rap)
            DEALLOCATE(todo)
            DEALLOCATE(is_in_range_rap)
            CLOSE(unit=21)
            exist_rap=.false.
        ENDIF
     ENDIF
  ENDDO
  CLOSE(unit=1)
  IF (exist_rap) CLOSE(unit=21)
!
!  Now find the high symmetry points. Note that here we neglect what has been
!  read in the representation file
!
  DO n=1,nks
     IF (n==1 .OR. n==nks) THEN
        high_symmetry(n) = .true.
     ELSE
        k1(:) = k(:,n) - k(:,n-1)
        k2(:) = k(:,n+1) - k(:,n)
        ps = ( k1(1)*k2(1) + k1(2)*k2(2) + k1(3)*k2(3) ) / &
         sqrt( k1(1)*k1(1) + k1(2)*k1(2) + k1(3)*k1(3) ) / &
         sqrt( k2(1)*k2(1) + k2(2)*k2(2) + k2(3)*k2(3) )
        high_symmetry(n) = (ABS(ps-1.d0) >1.0d-4)
!
!  The gamma point is a high symmetry point
!
        IF (k(1,n)**2+k(2,n)**2+k(3,n)**2 < 1.0d-9) high_symmetry(n)=.true.
     ENDIF
  ENDDO

  kx(1) = 0.d0
  DO n=2,nks
     IF (high_symmetry(n).AND.high_symmetry(n-1)) THEN
!
!   Account for the case in which in a plot a point k and a point k+G
!   are joined in a single point
!
        kx(n)=kx(n-1)
     ELSE
        kx(n) = kx(n-1) + sqrt ( (k(1,n)-k(1,n-1))**2 + &
                                 (k(2,n)-k(2,n-1))**2 + &
                                 (k(3,n)-k(3,n-1))**2 )
     ENDIF
  ENDDO

  DO n=1,nks
     DO i=1,nbnd
        emin = min(emin, e(i,n))
        emax = max(emax, e(i,n))
     ENDDO
  ENDDO
  PRINT '("Range:",2f10.4,"eV  Emin, Emax > ",$)', emin, emax
  READ(5,*) emin, emax

  is_in_range = .false.
  DO i=1,nbnd
     is_in_range(i) = any (e(i,1:nks) >= emin .and. e(i,1:nks) <= emax)
  ENDDO
  DO n=1,nks
     IF (high_symmetry(n)) THEN
        IF (n==1) THEN
           nlines=0
           npoints(1)=1
        ELSEIF (n==nks) THEN
           npoints(nlines+1) = npoints(nlines+1)+1
           nlines=nlines+1
        ELSE
           npoints(nlines+1) = npoints(nlines+1)+1
           nlines=nlines+1
           npoints(nlines+1) = 1
        ENDIF
        point(nlines+1)=n
        IF (n==1) THEN
           WRITE( stdout,'("high-symmetry point: ",3f7.4,&
                         &"   x coordinate   0.0000")') (k(i,n),i=1,3)
        ELSE
           WRITE( stdout,'("high-symmetry point: ",3f7.4,&
                         &"   x coordinate",f9.4)') (k(i,n),i=1,3), kx(n)
        ENDIF
     ELSE
        npoints(nlines+1) = npoints(nlines+1)+1
     ENDIF
  ENDDO
  !
  PRINT '("output file (xmgr) > ",$)'
  READ(5,'(a)', end=25, err=25)  filename
  IF (filename == ' ' ) THEN
     PRINT '("skipping ...")'
     GOTO 25
  ENDIF
  IF (.not.exist_rap) THEN
     OPEN (unit=2,file=filename,form='formatted',status='unknown',&
           iostat=ios)
     ! draw bands
     DO i=1,nbnd
        IF (is_in_range(i)) THEN
           IF ( mod(i,2) /= 0) THEN
              WRITE (2,'(2f10.4)') (kx(n), e(i,n),n=1,nks)
           ELSE
              WRITE (2,'(2f10.4)') (kx(n), e(i,n),n=nks,1,-1)
           ENDIF
        ENDIF
     ENDDO
     CLOSE (unit = 2)
  ELSE
!
!   In this case we write a diffent file for each line and for each
!   representation. Each file contains the bands of that representation.
!   The file is called filename.#line.#rap
!
!
!   First determine for each line how many representations are there
!
     DO ilines=1,nlines
        nrap(ilines)=0
        DO ipoint=1,npoints(ilines)-2
           n=point(ilines) + ipoint
           DO ibnd=1,nbnd
              nrap(ilines)=max(nrap(ilines),rap(ibnd,n))
           ENDDO
        ENDDO
        WRITE(6,*) 'lines nrap',ilines, nrap(ilines)
     ENDDO
!
!   Then, for each line and for each representation along that line
!
     DO ilines=1,nlines
        IF (nrap(ilines)==0) THEN
!
!   Along this line the symmetry decomposition has not been done.
!   Plot all the bands as in the standard case
!
           IF (ilines<10) THEN
              WRITE(filename1,'(a,".",i1)') trim(filename), ilines
           ELSE
              WRITE(filename1,'(a,".",i2)') trim(filename), ilines
           ENDIF
           OPEN (unit=2,file=filename1,form='formatted',status='unknown',&
                iostat=ios)
           ! draw bands
           DO i=1,nbnd
              IF (is_in_range(i)) THEN
                 IF ( mod(i,2) /= 0) THEN
                    WRITE (2,'(2f10.4)') (kx(n), e(i,n),n=point(ilines),&
                                                          point(ilines+1))
                 ELSE
                    WRITE (2,'(2f10.4)') (kx(n), e(i,n),n=point(ilines+1), &
                                                          point(ilines),-1 )
                 ENDIF
              ENDIF
           ENDDO
           CLOSE (unit = 2)
        ENDIF
        todo=.true.
        DO irap=1, nrap(ilines)
!
!     open a file
!
           IF (ilines>99.or.irap>12) THEN
              WRITE(6,'("too many lines or rap")')
              STOP
           ENDIF
           IF (ilines < 10) THEN
              IF (irap < 10 ) THEN
                 WRITE(filename1,'(a,".",i1,".",i1)') trim(filename),ilines,irap
              ELSE
                 WRITE(filename1,'(a,".",i1,".",i2)') trim(filename),ilines,irap
              ENDIF
           ELSE
              IF (irap < 10 ) THEN
                 WRITE(filename1,'(a,".",i2,".",i1)') trim(filename),ilines,irap
              ELSE
                 WRITE(filename1,'(a,".",i2,".",i2)') trim(filename),ilines,irap
              ENDIF
           ENDIF
           OPEN (unit=2,file=filename1,form='formatted',status='unknown',&
                 iostat=ios)
!  For each k point along this line selects only the bands which belong
!  to the irap representation
           nbnd_rapk=100000
           DO n=point(ilines)+1, point(ilines+1)-1
              nbnd_rapk(n)=0
              DO i=1,nbnd
                 IF (rap(i,n)==irap) THEN
                    nbnd_rapk(n) = nbnd_rapk(n) + 1
                    e_rap(nbnd_rapk(n),n)=e(i,n)
                 ENDIF
              ENDDO
           ENDDO
!
!   on the two high symmetry points the representation is different. So for each
!   band choose the closest eigenvalue available.
!
           DO i=1,nbnd_rapk(point(ilines)+1)
              mine=1.e8
              DO j=1,nbnd
                 IF (abs(e_rap(i,point(ilines)+1)-e(j,point(ilines)))<mine &
                                                        .and. todo(j,1)) THEN
                    e_rap(i,point(ilines))=e(j,point(ilines))
                    mine=abs( e_rap(i,point(ilines)+1)-e(j,point(ilines)))
                    jnow=j
                 ENDIF
              ENDDO
              todo(jnow,1)=.false.
           ENDDO
           DO i=1,nbnd_rapk(point(ilines+1)-1)
              mine=1.e8
              DO j=1,nbnd
                 IF (abs(e_rap(i,point(ilines+1)-1)- &
                          e(j,point(ilines+1)))<mine .and. todo(j,2)) THEN
                    e_rap(i,point(ilines+1))=e(j,point(ilines+1))
                    mine=abs(e_rap(i,point(ilines+1)-1)-e(j,point(ilines+1)) )
                    jnow=j
                 ENDIF
              ENDDO
              todo(jnow,2)=.false.
           ENDDO
           is_in_range_rap=.false.
           DO i=1,minval(nbnd_rapk)
              is_in_range_rap(i) = any (e_rap(i,point(ilines):point(ilines+1))&
                    >= emin .and. e(i,point(ilines):point(ilines+1)) <= emax)
           ENDDO
           DO i=1,minval(nbnd_rapk)
              IF (is_in_range_rap(i)) THEN
                 IF ( mod(i,2) /= 0) THEN
                    WRITE (2,'(2f10.4)') (kx(n), e_rap(i,n), &
                                        n=point(ilines),point(ilines+1))
                 ELSE
                    WRITE (2,'(2f10.4)') (kx(n), e_rap(i,n), &
                                       n=point(ilines+1),point(ilines),-1)
                 ENDIF
              ENDIF
           ENDDO
           IF (minval(nbnd_rapk)==0) THEN
              CLOSE (unit = 2,status='delete')
           ELSE
              CLOSE (unit = 2)
           ENDIF
        ENDDO
     ENDDO
  ENDIF
  PRINT '("bands in xmgr format written to file ",a)', filename
  !
25 CONTINUE
  IF (exist_rap) THEN
     DEALLOCATE(nbnd_rapk)
     DEALLOCATE(e_rap)
     DEALLOCATE(rap)
     DEALLOCATE(k_rap)
     DEALLOCATE(todo)
  ENDIF
  PRINT '("output file (ps) > ",$)'
  READ(5,'(a)',end=30,err=30)  filename
  IF (filename == ' ' ) THEN
     PRINT '("stopping ...")'
     GOTO 30
  ENDIF
  OPEN (unit=1,file=filename,form='formatted',status='unknown',&
       iostat=ios)
  PRINT '("Efermi > ",$)'
  READ(5,*) Ef
  PRINT '("deltaE, reference E (for tics) ",$)'
  READ(5,*) deltaE, eref
  !
  WRITE (1,'(a)') '%! PS-Adobe-1.0'
  WRITE (1,*) '/localdict 100 dict def'
  WRITE (1,*) 'localdict begin'
  WRITE (1,*) '% delete next line for insertion in a LaTeX file'
  WRITE (1,*) ' 0 0 moveto'
  WRITE (1,*) 'gsave'
  WRITE (1,*) '/nm  {newpath moveto} def'
  WRITE (1,*) '/riga {newpath moveto lineto stroke} def'
  WRITE (1,*) '/banda {3 1 roll moveto {lineto} repeat stroke} def'
  WRITE (1,*) '/dot {newpath  1 0 360 arc fill} def'
  WRITE (1,*) '/Times-Roman findfont 12 scalefont setfont'
  WRITE (1,*) 'currentpoint translate'
  WRITE (1,*) '% Landscape: uncomment next line'
  WRITE (1,*) ' 90 rotate 0 21 neg 28.451 mul translate 1.5 1.5 scale'
  WRITE (1,*) '% Landscape:   comment next line'
  WRITE (1,*) '% 1.2 1.2 scale'
  WRITE (1,'(2(f8.3,1x)," translate")') x0, y0
  WRITE (1,*) '0 setgray 0.5 setlinewidth'
  ! draw tics on axis
  ni=nint((eref-emin)/deltaE)+1
  nf=nint((emax-eref)/deltaE)+1
  DO i=-ni,nf
     etic=eref+i*deltaE
     IF (etic >= emin .and. etic <= emax) THEN
        WRITE (1,'(2(f8.3,1x)," moveto -5 0 rlineto stroke")') &
             0.0,(etic-emin)*ydim/(emax-emin)
        WRITE (1,'(2(f8.3,1x)," moveto (",f5.1,") show")')   &
             -30.,(etic-emin)*ydim/(emax-emin), etic-eref
     ENDIF
  ENDDO
  ! draw the Fermi Energy
  IF (Ef > emin .and. Ef < emax) THEN
     WRITE (1,'("[2 4] 0 setdash newpath ",2(f8.3,1x), " moveto ")') &
          0.0, (Ef-emin)/(emax-emin)*ydim
     WRITE (1,'(2(f8.3,1x)," lineto stroke [] 0 setdash")') &
          xdim, (Ef-emin)/(emax-emin)*ydim
  ENDIF
  ! draw axis and set clipping region
  WRITE (1,*) '1 setlinewidth'
  WRITE (1,'(8(f8.3,1x))') 0.0,0.0,0.0,ydim,xdim,ydim,xdim,0.0
  WRITE (1,*) 'newpath moveto lineto lineto lineto closepath clip stroke'
  WRITE (1,*) '0.5 setlinewidth'
  ! draw high-symmetry lines
  DO n=1,nks
     IF (high_symmetry(n)) THEN
        WRITE (1,'(4(f8.3,1x)," riga")') &
             kx(n)*xdim/kx(nks), 0.0, kx(n)*xdim/kx(nks), ydim
     ENDIF
     DO i=1,nbnd
        IF (is_in_range(i)) WRITE (1,'(2(f8.3,1x)," dot")' ) &
             kx(n)*xdim/kx(nks), (e(i,n)-emin)*ydim/(emax-emin)
     ENDDO
  ENDDO
  ! draw bands
  ALLOCATE (k_interp(4*nks), e_interp(4*nks), coef_interp(nks,4))
  DO i=1,nbnd
     IF (is_in_range(i)) THEN
        ! No interpolation:
        !         write (1,'(9(f8.3,1x))') ( kx(n)*xdim/kx(nks), &
        !             (e(i,n)-emin)*ydim/(emax-emin),n=nks,1,-1)
        !         write (1,'(i4," banda")' ) nks-1
        ! Spline interpolation with twice as many points:
        !
        ni=1
        nf=1
        DO nl=1,nlines
           ni=nf
           nf=nf + npoints(nl)-1
           n_interp= 2*(nf-ni)+1
           DO n=1,n_interp
              k_interp(n)=kx(ni)+(n-1)*(kx(nf)-kx(ni))/(n_interp-1)
           ENDDO
           DO n=ni,nf
              e_in(n-ni+1)=e(i,n)
           ENDDO
           CALL spline_interpol ( kx(ni), e_in, nf-ni+1, &
                k_interp, e_interp, n_interp )
           WRITE (1,'(9(f8.3,1x))') ( k_interp(n)*xdim/kx(nks), &
                (e_interp(n)-emin)*ydim/(emax-emin),n=n_interp,1,-1)
           WRITE (1,'(i4," banda")' ) n_interp-1
        ENDDO
     ENDIF
  ENDDO

  WRITE (1,*) 'grestore'
  WRITE (1,*) '% delete next lines for insertion in a tex file'
  WRITE (1,'(a)') '%%Page'
  WRITE (1,*) 'showpage'
  CLOSE (unit=1)
  PRINT '("bands in PostScript format written to file ",a)', filename
30 CONTINUE

  STOP
20 PRINT '("Error reading k-point # ",i4)', n
  STOP

CONTAINS

SUBROUTINE spline_interpol (xin, yin, nin, xout, yout, nout)

  ! xin and xout should be in increasing order, with
  ! xout(1) <= xin(1), xout(nout) <= xin(nin)

  IMPLICIT NONE
  INTEGER, INTENT(in) :: nin, nout
  real, INTENT(in)  :: xin(nin), yin(nin), xout(nout)
  real, INTENT(out) :: yout(nout)
  ! work space (automatically allocated)
  real :: d2y(nin)
  real :: dy1, dyn

  dy1 = (yin(2)-yin(1))/(xin(2)-xin(1))
  dyn = 0.0

  CALL spline( xin, yin, nin, dy1, dyn, d2y)
  CALL splint( nin, xin, yin, d2y, nout, xout, yout)

  RETURN
END SUBROUTINE spline_interpol

SUBROUTINE spline(x, y, n, yp1, ypn, d2y)

  IMPLICIT NONE
  INTEGER, INTENT(in) :: n
  real, INTENT(in) :: x(n), y(n), yp1, ypn
  real, INTENT(out):: d2y(n)
  ! work space (automatically allocated)
  real :: work(n)
  INTEGER :: i, k
  real :: sig, p, qn, un

  d2y(1)=-0.5
  work(1)=(3.0/(x(2)-x(1)))*((y(2)-y(1))/(x(2)-x(1))-yp1)

  DO i=2,n-1
     sig=(x(i)-x(i-1))/(x(i+1)-x(i-1))
     p=sig*d2y(i-1)+2.0
     d2y(i)=(sig-1.0)/p
     work(i)=(6.0*((y(i+1)-y(i))/(x(i+1)-x(i))-(y(i)-y(i-1)) &
          /(x(i)-x(i-1)))/(x(i+1)-x(i-1))-sig*work(i-1))/p
  ENDDO
  qn=0.5
  un=(3.0/(x(n)-x(n-1)))*(ypn-(y(n)-y(n-1))/(x(n)-x(n-1)))

  d2y(n)=(un-qn*work(n-1))/(qn*d2y(n-1)+1.0)
  DO k=n-1,1,-1
     d2y(k)=d2y(k)*d2y(k+1)+work(k)
  ENDDO

  RETURN
END SUBROUTINE spline


SUBROUTINE splint (nspline, xspline, yspline, d2y, nfit, xfit, yfit)

  IMPLICIT NONE
  ! input
  INTEGER, INTENT(in) :: nspline, nfit
  real, INTENT(in) :: xspline(nspline), yspline(nspline), xfit(nfit), &
       d2y(nspline)
  real, INTENT(out) :: yfit(nfit)
  INTEGER :: klo, khi, i
  real :: a, b, h

  klo=1
  DO i=1,nfit
     DO khi=klo+1, nspline
        IF(xspline(khi) >= xfit(i)) THEN
           IF(xspline(khi-1) <= xfit(i)) THEN
              klo = khi-1
           ELSE
              IF (klo == 1 .and. khi-1 == 1) THEN
                 ! the case xfit(i) < xspline(1) should not happen
                 ! but since it may be due to a numerical artifact
                 ! we just continue
                 PRINT *, '  SPLINT WARNING: xfit(i) < xspline(1)', &
                      xfit(i), xspline(1)
              ELSE
                 STOP '  SPLINT ERROR: xfit not properly ordered'
              ENDIF
           ENDIF
           h= xspline(khi) - xspline(klo)
           a= (xspline(khi)-xfit(i))/h
           b= (xfit(i)-xspline(klo))/h

           yfit(i) = a*yspline(klo) + b*yspline(khi) &
                + ( (a**3-a)*d2y(klo) + (b**3-b)*d2y(khi)  )*h*h/6.0
           GOTO 10
        ENDIF
     ENDDO

     ! the case xfit(i) > xspline(nspline) should also not happen
     ! but again it may be due to a numerical artifact
     ! A properly chosen extrapolation formula should be used here
     ! (and in the case  xfit(i) < xspline(1) above as well) but
     ! I am too lazy to write one - PG

     PRINT *, '  SPLINT WARNING: xfit(i) > xspline(nspline)', &
                      xfit(i), xspline(nspline)
     khi = klo+1
     h= xspline(khi) - xspline(klo)
     a= (xspline(khi)-xfit(i))/h
     b= (xfit(i)-xspline(klo))/h

     yfit(i) = a*yspline(klo) + b*yspline(khi) &
          + ( (a**3-a)*d2y(klo) + (b**3-b)*d2y(khi)  )*h*h/6.0
     !
10   CONTINUE
  ENDDO

  RETURN
END SUBROUTINE splint

END PROGRAM plotband

