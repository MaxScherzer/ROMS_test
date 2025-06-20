#include "cppdefs.h"
      MODULE vorticity_mod
!
!git $Id$
!=======================================================================
!  Copyright (c) 2002-2025 The ROMS Group                              !
!    Licensed under a MIT/X style license                              !
!    See License_ROMS.md                                               !
!================================================== Hernan G. Arango ===
!                                                                      !
!  This routine computes relative (s-1) and  potential (m-1 s-1)       !
!  vorticity for an adiabatic Boussinesq fluid where the potential     !
!  density is conserved:                                               !
!                                                                      !
!    pvor = 1/rho0 dot_product(avor, grad(pden))                       !
!                                                                      !
!  where "avor" is the absolute (relative plus planetary) vorticity    !
!  and "pden" is the potential density (a conserved quantity).         !
!                                                                      !
!    avor = rvor + f                                                   !
!                                                                      !
!  In curvilinear coordinates, the vertical component of relative      !
!  vorticity and potential vorticity are:                              !
!  are:                                                                !
!                                                                      !
!    rvor = mn * [d(v/n)/d(xi) - d(u/m)/d(eta)]                        !
!                                                                      !
!    pvor = mn/rho0 * [f/mn +                                          !
!                                                                      !
!                      d(v/n)/d(xi) - d(u/m)/d(eta)] * d(pden)/d(z) +  !
!                                                                      !
!           1/rho0 * [1/n d(pden)/d(eta) d(u)/d(z) -                   !
!                                                                      !
!                     1/m d(pden)/d(xi)  d(v)/d(z)]                    !
!                                                                      !
!  In addition, the vertically integrated (shallow water) relative     !
!  and potential vorticity are computed.                               !
!                                                                      !
!  The relative and potential vorticity is discretized at horizontal   !
!  PSI-points and vertical RHO-points.                                 !
!                                                                      !
!=======================================================================
!
      USE mod_param
      USE mod_average
      USE mod_param
      USE mod_grid
      USE mod_ncparam
      USE mod_ocean
      USE mod_scalars
!
      USE exchange_2d_mod, ONLY : exchange_p2d_tile
# ifdef SOLVE3D
      USE exchange_3d_mod, ONLY : exchange_p3d_tile
# endif
# ifdef DISTRIBUTE
      USE mp_exchange_mod, ONLY : mp_exchange2d
#  ifdef SOLVE3D
      USE mp_exchange_mod, ONLY : mp_exchange3d
#  endif
# endif
!
      implicit none
!
      PUBLIC  :: pvorticity2d
      PUBLIC  :: rvorticity2d
#ifdef SOLVE3D
      PUBLIC  :: pvorticity3d
      PUBLIC  :: rvorticity3d
#endif
#if defined AVERAGES    || \
   (defined AD_AVERAGES && defined ADJOINT) || \
   (defined RP_AVERAGES && defined TL_IOMS) || \
   (defined TL_AVERAGES && defined TANGENT)
      PUBLIC  :: vorticity_avg
      PUBLIC  :: vorticity_avg_tile
#endif
      PRIVATE
!
      CONTAINS
!
!***********************************************************************
      SUBROUTINE pvorticity2d (ng, model, tile,                         &
     &                         LBi, UBi, LBj, UBj,                      &
     &                         kout,                                    &
#ifdef MASKING
     &                         pmask,                                   &
#endif
     &                         f, h, om_u, on_v, pm, pn,                &
     &                         ubar, vbar, zeta,                        &
     &                         pvor2d)
!***********************************************************************
!
!  Imported variable declarations.
!
      integer,  intent(in)  :: ng, model, tile
      integer,  intent(in)  :: LBi, UBi, LBj, UBj
      integer,  intent(in)  :: kout
!
#ifdef ASSUMED_SHAPE
# ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:,LBj:)
# endif
      real(r8), intent(in)  :: f(LBi:,LBj:)
      real(r8), intent(in)  :: h(LBi:,LBj:)
      real(r8), intent(in)  :: om_u(LBi:,LBj:)
      real(r8), intent(in)  :: on_v(LBi:,LBj:)
      real(r8), intent(in)  :: pm(LBi:,LBj:)
      real(r8), intent(in)  :: pn(LBi:,LBj:)
      real(r8), intent(in)  :: ubar(LBi:,LBj:,:)
      real(r8), intent(in)  :: vbar(LBi:,LBj:,:)
      real(r8), intent(in)  :: zeta(LBi:,LBj:,:)
      real(r8), intent(out) :: pvor2d(LBi:,LBj:)

#else

# ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:UBi,LBj:UBj)
# endif
      real(r8), intent(in)  :: f(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: h(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: om_u(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: on_v(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pm(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pn(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: ubar(LBi:UBi,LBj:UBj,:)
      real(r8), intent(in)  :: vbar(LBi:UBi,LBj:UBj,:)
      real(r8), intent(in)  :: zeta(LBi:UBi,LBj:UBj,:)
      real(r8), intent(out) :: pvor2d(LBi:UBi,LBj:UBj)
#endif
!
!  Local variable declarations.
!
      integer  :: i, j
      real(r8) :: cff, fomn_p, dUde_p, dVdx_p

#include "set_bounds.h"
!
!-----------------------------------------------------------------------
!  Compute 2D potential vorticity.
!-----------------------------------------------------------------------
!
!  Potential vorticity (meter-1 second-1) at PSI-points.
!
      DO j=Jstr,JendR
        DO i=Istr,IendR
          cff=0.0625_r8*                                                &
     &        (pm(i-1,j-1)+pm(i-1,j)+pm(i,j-1)+pm(i,j))*                &
     &        (pn(i-1,j-1)+pn(i-1,j)+pn(i,j-1)+pn(i,j))
          fomn_p=0.25_r8*(f(i-1,j-1)+f(i-1,j)+f(i,j-1)+f(i,j))/cff
          cff=pm(i,j)*pn(i,j)
          dVdx_p=on_v(i  ,j)*vbar(i  ,j,kout)-                          &
     &           on_v(i-1,j)*vbar(i-1,j,kout)
#ifdef MASKING
          dVdx_p=dVdx_p*pmask(i,j)
#endif
          dUde_p=om_u(i,j  )*ubar(i,j  ,kout)-                          &
     &           om_u(i,j-1)*ubar(i,j-1,kout)
#ifdef MASKING
          dUde_p=dUde_p*pmask(i,j)
#endif
          pvor2d(i,j)=cff*((fomn_p+dVdx_p-dUde_p)/                      &
     &                     (h(i,j)+zeta(i,j,kout)))
        END DO
      END DO
!
!  Exchange boundary information.
!
      IF (EWperiodic(ng).or.NSperiodic(ng)) THEN
        CALL exchange_p2d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj,                     &
     &                          pvor2d)
      END IF

#ifdef DISTRIBUTE
! 
      CALL mp_exchange2d (ng, tile, model, 1,                           &
     &                    LBi, UBi, LBj, UBj,                           &
     &                    NghostPoints, EWperiodic(ng), NSperiodic(ng), &
     &                    pvor2d)
#endif
!
      RETURN
      END SUBROUTINE pvorticity2d
!
!***********************************************************************
      SUBROUTINE rvorticity2d (ng, model, tile,                         &
     &                         LBi, UBi, LBj, UBj,                      &
     &                         kout,                                    &
#ifdef MASKING
     &                         pmask,                                   &
#endif
     &                         om_u, on_v, pm, pn,                      &
     &                         ubar, vbar,                              &
     &                         rvor2d)
!***********************************************************************
!
!  Imported variable declarations.
!
      integer, intent(in)   :: ng, model, tile
      integer, intent(in)   :: LBi, UBi, LBj, UBj
      integer, intent(in)   :: kout
!
#ifdef ASSUMED_SHAPE
# ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:,LBj:)
# endif
      real(r8), intent(in)  :: om_u(LBi:,LBj:)
      real(r8), intent(in)  :: on_v(LBi:,LBj:)
      real(r8), intent(in)  :: pm(LBi:,LBj:)
      real(r8), intent(in)  :: pn(LBi:,LBj:)
      real(r8), intent(in)  :: ubar(LBi:,LBj:,:)
      real(r8), intent(in)  :: vbar(LBi:,LBj:,:)
      real(r8), intent(out) :: rvor2d(LBi:,LBj:)

#else

# ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:UBi,LBj:UBj)
# endif
      real(r8), intent(in)  :: om_u(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: on_v(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pm(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pn(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: ubar(LBi:UBi,LBj:UBj,:)
      real(r8), intent(in)  :: vbar(LBi:UBi,LBj:UBj,:)
      real(r8), intent(out) :: rvor2d(LBi:UBi,LBj:UBj)
#endif
!
!  Local variable declarations.
!
      integer  :: i, j
      real(r8) :: cff, dUde_p, dVdx_p

#include "set_bounds.h"
!
!-----------------------------------------------------------------------
!  Compute 2D relative vorticity.
!-----------------------------------------------------------------------
!
!  Compute barotropic relative vorticity (second-1) at horizontal
!  PSI-points.
!
      DO j=Jstr,JendR
        DO i=Istr,IendR
          cff=0.0625_r8*                                                &
     &        (pm(i-1,j-1)+pm(i-1,j)+pm(i,j-1)+pm(i,j))*                &
     &        (pn(i-1,j-1)+pn(i-1,j)+pn(i,j-1)+pn(i,j))
          dVdx_p=on_v(i  ,j)*vbar(i  ,j,kout)-                          &
     &           on_v(i-1,j)*vbar(i-1,j,kout)
#ifdef MASKING
          dVdx_p=dVdx_p*pmask(i,j)
#endif
          dUde_p=om_u(i,j  )*ubar(i,j  ,kout)-                          &
     &           om_u(i,j-1)*ubar(i,j-1,kout)
#ifdef MASKING
          dUde_p=dUde_p*pmask(i,j)
#endif
          rvor2d(i,j)=cff*(dVdx_p-dUde_p)
        END DO
      END DO
!
!  Exchange boundary information.
!
      IF (EWperiodic(ng).or.NSperiodic(ng)) THEN
        CALL exchange_p2d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj,                     &
     &                          rvor2d)
      END IF

#ifdef DISTRIBUTE
      CALL mp_exchange2d (ng, tile, model, 1,                           &
     &                    LBi, UBi, LBj, UBj,                           &
     &                    NghostPoints, EWperiodic(ng), NSperiodic(ng), &
     &                    rvor2d)
#endif
!
      RETURN
      END SUBROUTINE rvorticity2d

#ifdef SOLVE3D
!
!***********************************************************************
      SUBROUTINE pvorticity3d (ng, model, tile,                         &
     &                         LBi, UBi, LBj, UBj,                      &
     &                         IminS, ImaxS, JminS, JmaxS,              &
     &                         nout,                                    &
# ifdef MASKING
     &                         pmask, umask, vmask,                     &
# endif
     &                         f, om_u, on_v, pm, pn, z_r,              &
     &                         pden, u, v,                              &
     &                         pvor3d)
!***********************************************************************
!
!  Imported variable declarations.
!
      integer,  intent(in)  :: ng, model, tile
      integer,  intent(in)  :: LBi, UBi, LBj, UBj
      integer,  intent(in)  :: IminS, ImaxS, JminS, JmaxS
      integer,  intent(in)  :: nout
!
# ifdef ASSUMED_SHAPE
#  ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:,LBj:)
      real(r8), intent(in)  :: umask(LBi:,LBj:)
      real(r8), intent(in)  :: vmask(LBi:,LBj:)
#  endif
      real(r8), intent(in)  :: f(LBi:,LBj:)
      real(r8), intent(in)  :: om_u(LBi:,LBj:)
      real(r8), intent(in)  :: on_v(LBi:,LBj:)
      real(r8), intent(in)  :: pm(LBi:,LBj:)
      real(r8), intent(in)  :: pn(LBi:,LBj:)
      real(r8), intent(in)  :: z_r(LBi:,LBj:,:)
      real(r8), intent(in)  :: pden(LBi:,LBj:,:)
      real(r8), intent(in)  :: u(LBi:,LBj:,:,:)
      real(r8), intent(in)  :: v(LBi:,LBj:,:,:)
      real(r8), intent(out) :: pvor3d(LBi:,LBj:,:)

# else

#  ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: umask(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: vmask(LBi:UBi,LBj:UBj)
#  endif
      real(r8), intent(in)  :: f(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: om_u(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: on_v(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pm(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pn(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: z_r(LBi:UBi,LBj:UBj,N(ng))
      real(r8), intent(in)  :: pden(LBi:UBi,LBj:UBj,N(ng))
      real(r8), intent(in)  :: u(LBi:UBi,LBj:UBj,N(ng),2)
      real(r8), intent(in)  :: v(LBi:UBi,LBj:UBj,N(ng),2)
      real(r8), intent(out) :: rvor3d(LBi:UBi,LBj:UBj,N(ng))
# endif
!
!  Local variable declarations.
!
      integer  :: i, j, k, k1, k2
!
      real(r8) :: cff, fomn_p, orho0
      real(r8) :: dRde_pr, dRdx_pr, dRdz_pr, dUdz_pr, dVdz_pr

      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dRde
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dRdx
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dUde
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dVdx

      real(r8), dimension(IminS:ImaxS,JminS:JmaxS,2) :: dRdz
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS,2) :: dUdz
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS,2) :: dVdz

# include "set_bounds.h"
!
!-----------------------------------------------------------------------
!  Compute 3D potential vorticity.
!-----------------------------------------------------------------------
!
!  Compute horizontal and vertical gradients.  Notice the recursive
!  blocking sequence for vertical placement of the gradients is:
!
!      dRdz,dUdz,dVdz(:,:,k1) k-1/2   W-points
!      dRdz,dUdz,dVdz(:,:,k2) k+1/2   W-points
!
      orho0=1.0_r8/rho0

      k2=1
      K_LOOP : DO k=0,N(ng)
        k1=k2
        k2=3-k1
        IF (k.gt.0) THEN
          DO j=Jstr-1,JendR
            DO i=Istr,IendR
              cff=0.5_r8*(pm(i,j)+pm(i-1,j))
# ifdef MASKING
              cff=cff*umask(i,j)
# endif
              dRdx(i,j)=cff*(pden(i  ,j,k)-                             &
     &                       pden(i-1,j,k))
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr-1,IendR
              cff=0.5_r8*(pn(i,j)+pn(i,j-1))
# ifdef MASKING
              cff=cff*vmask(i,j)
# endif
              dRde(i,j)=cff*(pden(i,j  ,k)-                             &
     &                       pden(i,j-1,k))
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr,IendR
              dUde(i,j)=om_u(i,j  )*u(i,j  ,k,nout)-                    &
     &                  om_u(i,j-1)*u(i,j-1,k,nout)
# ifdef MASKING
              dUde(i,j)=dUde(i,j)*pmask(i,j)
# endif
              dVdx(i,j)=on_v(i  ,j)*v(i  ,j,k,nout)-                    &
     &                  on_v(i-1,j)*v(i-1,j,k,nout)
# ifdef MASKING
              dVdx(i,j)=dVdx(i,j)*pmask(i,j)
# endif
            END DO
          END DO
        END IF
        IF ((k.eq.0).or.(k.eq.N(ng))) THEN
          DO j=Jstr-1,JendR
            DO i=Istr-1,IendR
              dRdz(i,j,k2)=0.0_r8
            END DO
          END DO
          DO j=Jstr-1,JendR
            DO i=Istr,IendR
              dUdz(i,j,k2)=0.0_r8
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr-1,IendR
              dVdz(i,j,k2)=0.0_r8
            END DO
          END DO
        ELSE
          DO j=Jstr-1,JendR
            DO i=Istr-1,IendR
              cff=1.0_r8/(z_r(i,j,k+1)-z_r(i,j,k))
              dRdz(i,j,k2)=cff*(pden(i,j,k+1)-                          &
     &                          pden(i,j,k  ))
            END DO
          END DO
          DO j=Jstr-1,JendR
            DO i=Istr,IendR
              cff=1.0_r8/(0.5_r8*(z_r(i-1,j,k+1)-z_r(i-1,j,k)+          &
     &                            z_r(i  ,j,k+1)-z_r(i  ,j,k)))
              dUdz(i,j,k2)=cff*(u(i,j,k+1,nout)-                        &
     &                          u(i,j,k  ,nout))
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr-1,IendR
              cff=1.0_r8/(0.5_r8*(z_r(i,j-1,k+1)-z_r(i,j-1,k)+          &
     &                            z_r(i,j  ,k+1)-z_r(i,j  ,k)))
              dVdz(i,j,k2)=cff*(v(i,j,k+1,nout)-                        &
     &                          v(i,j,k  ,nout))
            END DO
          END DO
        END IF
!
!  Compute potential vorticity (meter-1 second-1) at horizontal
!  PSI-points and vertical RHO-points.
!
        IF (k.gt.0) THEN
          DO j=Jstr,JendR
            DO i=Istr,IendR
              cff=0.0625_r8*                                            &
     &            (pm(i-1,j-1)+pm(i-1,j)+pm(i,j-1)+pm(i,j))*            &
     &            (pn(i-1,j-1)+pn(i-1,j)+pn(i,j-1)+pn(i,j))
              fomn_p=0.25_r8*(f(i-1,j-1)+f(i-1,j)+f(i,j-1)+f(i,j))/cff
              dRde_pr=dRde(i-1,j  )+dRde(i,j)
              dRdx_pr=dRdx(i  ,j-1)+dRdx(i,j)
              dRdz_pr=0.125_r8*(dRdz(i-1,j-1,k1)+dRdz(i-1,j-1,k2)+      &
     &                          dRdz(i  ,j-1,k1)+dRdz(i  ,j-1,k2)+      &
     &                          dRdz(i-1,j  ,k1)+dRdz(i-1,j  ,k2)+      &
     &                          dRdz(i  ,j  ,k1)+dRdz(i  ,j  ,k2))
              dUdz_pr=dUdz(i  ,j-1,k1)+dUdz(i  ,j-1,k2)+                &
     &                dUdz(i  ,j  ,k1)+dUdz(i  ,j  ,k2)
              dVdz_pr=dVdz(i-1,j  ,k1)+dVdz(i-1,j  ,k2)+                &
     &                dVdz(i  ,j  ,k1)+dVdz(i  ,j  ,k2)
              pvor3d(i,j,k)=orho0*                                      &
     &                      (cff*dRdz_pr*(fomn_p+                       &
     &                                    dVdx(i,j)-dUde(i,j))+         &
     &                       0.125_r8*(dUdz_pr*dRde_pr-dVdz_pr*dRdx_pr))
            END DO
          END DO
        END IF
      END DO K_LOOP
!
!  Exchange boundary data.
!
      IF (EWperiodic(ng).or.NSperiodic(ng)) THEN
        CALL exchange_p3d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj, 1, N(ng),           &
     &                          pvor3d)
      END IF

# ifdef DISTRIBUTE
!
      CALL mp_exchange3d (ng, tile, model, 1,                           &
     &                    LBi, UBi, LBj, UBj, 1, N(ng),                 &
     &                    NghostPoints, EWperiodic(ng), NSperiodic(ng), &
     &                    pvor3d)
# endif
!
      RETURN
      END SUBROUTINE pvorticity3d
!
!***********************************************************************
      SUBROUTINE rvorticity3d (ng, model, tile,                         &
     &                         LBi, UBi, LBj, UBj,                      &
     &                         nout,                                    &
# ifdef MASKING
     &                         pmask,                                   &
# endif
     &                         om_u, on_v, pm, pn,                      &
     &                         u, v,                                    &
     &                         rvor3d)
!***********************************************************************
!
!  Imported variable declarations.
!
      integer,  intent(in)  :: ng, model, tile
      integer,  intent(in)  :: LBi, UBi, LBj, UBj
      integer,  intent(in)  :: nout

# ifdef ASSUMED_SHAPE
#  ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:,LBj:)
#  endif
      real(r8), intent(in)  :: om_u(LBi:,LBj:)
      real(r8), intent(in)  :: on_v(LBi:,LBj:)
      real(r8), intent(in)  :: pm(LBi:,LBj:)
      real(r8), intent(in)  :: pn(LBi:,LBj:)
      real(r8), intent(in)  :: u(LBi:,LBj:,:,:)
      real(r8), intent(in)  :: v(LBi:,LBj:,:,:)
      real(r8), intent(out) :: rvor3d(LBi:,LBj:,:)

# else

#  ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:UBi,LBj:UBj)
#  endif
      real(r8), intent(in)  :: om_u(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: on_v(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pm(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pn(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: u(LBi:UBi,LBj:UBj,N(ng),2)
      real(r8), intent(in)  :: v(LBi:UBi,LBj:UBj,N(ng),2)
      real(r8), intent(out) :: rvor3d(LBi:UBi,LBj:UBj,N(ng))
# endif
!
!  Local variable declarations.
!
      integer  :: i, j, k
      real(r8) :: cff, dUde_p, dVdx_p

# include "set_bounds.h"
!
!-----------------------------------------------------------------------
!  Compute 3D relative vorticity.
!-----------------------------------------------------------------------
!
!  Compute relative vorticity (second-1) at horizontal PSI-points and
!  vertical RHO-points.
!
      DO k=1,N(ng)
        DO j=Jstr,JendR
          DO i=Istr,IendR
            cff=0.0625_r8*                                              &
     &          (pm(i-1,j-1)+pm(i-1,j)+pm(i,j-1)+pm(i,j))*              &
     &          (pn(i-1,j-1)+pn(i-1,j)+pn(i,j-1)+pn(i,j))
            dUde_p=om_u(i,j  )*u(i,j  ,k,nout)-                         &
     &             om_u(i,j-1)*u(i,j-1,k,nout)
# ifdef MASKING
            dUde_p=dUde_p*pmask(i,j)
# endif
            dVdx_p=on_v(i  ,j)*v(i  ,j,k,nout)-                         &
     &             on_v(i-1,j)*v(i-1,j,k,nout)
# ifdef MASKING
            dVdx_p=dVdx_p*pmask(i,j)
# endif
            rvor3d(i,j,k)=cff*(dVdx_p-dUde_p)
          END DO
        END DO
      END DO
!
!  Exchange boundary data.
!
      IF (EWperiodic(ng).or.NSperiodic(ng)) THEN
        CALL exchange_p3d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj, 1, N(ng),           &
     &                          rvor3d)
      END IF

# ifdef DISTRIBUTE
!
      CALL mp_exchange3d (ng, tile, model, 1,                           &
     &                    LBi, UBi, LBj, UBj, 1, N(ng),                 &
     &                    NghostPoints, EWperiodic(ng), NSperiodic(ng), &
     &                    rvor3d)
# endif
!
      RETURN
      END SUBROUTINE rvorticity3d
#endif

#if defined AVERAGES    || \
   (defined AD_AVERAGES && defined ADJOINT) || \
   (defined RP_AVERAGES && defined TL_IOMS) || \
   (defined TL_AVERAGES && defined TANGENT)
!
!***********************************************************************
      SUBROUTINE vorticity_avg (ng, model, tile)
!***********************************************************************
!
      USE mod_stepping
!
!  Imported variable declarations.
!
      integer, intent(in) :: ng, model, tile
!
!  Local variable declarations.
!
      character (len=*), parameter :: MyFile =                          &
     &  __FILE__
!
# include "tile.h"
!
# ifdef PROFILE
      CALL wclock_on (ng, model, 5, __LINE__, MyFile)
# endif
      CALL vorticity_avg_tile (ng, model, tile,                         &
     &                         LBi, UBi, LBj, UBj,                      &
     &                         IminS, ImaxS, JminS, JmaxS,              &
# ifdef SOLVE3D
     &                         KOUT, NOUT,                              &
# else
     &                         KOUT,                                    &
# endif
# ifdef MASKING
     &                         GRID(ng) % pmask,                        &
     &                         GRID(ng) % umask,                        &
     &                         GRID(ng) % vmask,                        &
# endif
     &                         GRID(ng) % f,                            &
     &                         GRID(ng) % h,                            &
     &                         GRID(ng) % om_u,                         &
     &                         GRID(ng) % on_v,                         &
     &                         GRID(ng) % pm,                           &
     &                         GRID(ng) % pn,                           &
# ifdef SOLVE3D
     &                         GRID(ng) % z_r,                          &
     &                         OCEAN(ng) % pden,                        &
     &                         OCEAN(ng) % u,                           &
     &                         OCEAN(ng) % v,                           &
# endif
     &                         OCEAN(ng) % ubar,                        &
     &                         OCEAN(ng) % vbar,                        &
     &                         OCEAN(ng) % zeta,                        &
# ifdef SOLVE3D
     &                         AVERAGE(ng) % avgpvor3d,                 &
     &                         AVERAGE(ng) % avgrvor3d,                 &
# endif
     &                         AVERAGE(ng) % avgpvor2d,                 &
     &                         AVERAGE(ng) % avgrvor2d)

# ifdef PROFILE
      CALL wclock_off (ng, model, 5, __LINE__, MyFile)
# endif
!
      RETURN
      END SUBROUTINE vorticity_avg
!
!***********************************************************************
      SUBROUTINE vorticity_avg_tile (ng, model, tile,                   &
     &                               LBi, UBi, LBj, UBj,                &
     &                               IminS, ImaxS, JminS, JmaxS,        &
# ifdef SOLVE3D
     &                               kout, nout,                        &
# else
     &                               kout,                              &
# endif
# ifdef MASKING
     &                               pmask, umask, vmask,               &
# endif
     &                               f, h, om_u, on_v, pm, pn,          &
# ifdef SOLVE3D
     &                               z_r, pden, u, v,                   &
# endif
     &                               ubar, vbar, zeta,                  &
# ifdef SOLVE3D
     &                               pvor, rvor,                        &
# endif
     &                               pvor_bar, rvor_bar)
!***********************************************************************
!
!  Imported variable declarations.
!
      integer,  intent(in)  :: ng, model, tile
      integer,  intent(in)  :: LBi, UBi, LBj, UBj
      integer,  intent(in)  :: IminS, ImaxS, JminS, JmaxS
# ifdef SOLVE3D
      integer,  intent(in)  :: kout, nout
# else
      integer,  intent(in)  :: kout
# endif
!
# ifdef ASSUMED_SHAPE
#  ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:,LBj:)
      real(r8), intent(in)  :: umask(LBi:,LBj:)
      real(r8), intent(in)  :: vmask(LBi:,LBj:)
#  endif
      real(r8), intent(in)  :: f(LBi:,LBj:)
      real(r8), intent(in)  :: h(LBi:,LBj:)
      real(r8), intent(in)  :: om_u(LBi:,LBj:)
      real(r8), intent(in)  :: on_v(LBi:,LBj:)
      real(r8), intent(in)  :: pm(LBi:,LBj:)
      real(r8), intent(in)  :: pn(LBi:,LBj:)
#  ifdef SOLVE3D
      real(r8), intent(in)  :: z_r(LBi:,LBj:,:)
      real(r8), intent(in)  :: pden(LBi:,LBj:,:)
      real(r8), intent(in)  :: u(LBi:,LBj:,:,:)
      real(r8), intent(in)  :: v(LBi:,LBj:,:,:)
#  endif
      real(r8), intent(in)  :: ubar(LBi:,LBj:,:)
      real(r8), intent(in)  :: vbar(LBi:,LBj:,:)
      real(r8), intent(in)  :: zeta(LBi:,LBj:,:)

      real(r8), intent(out) :: pvor_bar(LBi:,LBj:)
      real(r8), intent(out) :: rvor_bar(LBi:,LBj:)
#  ifdef SOLVE3D
      real(r8), intent(out) :: pvor(LBi:,LBj:,:)
      real(r8), intent(out) :: rvor(LBi:,LBj:,:)
#  endif

# else

#  ifdef MASKING
      real(r8), intent(in)  :: pmask(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: umask(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: vmask(LBi:UBi,LBj:UBj)
#  endif
      real(r8), intent(in)  :: f(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: h(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: om_u(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: on_v(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pm(LBi:UBi,LBj:UBj)
      real(r8), intent(in)  :: pn(LBi:UBi,LBj:UBj)
#  ifdef SOLVE3D
      real(r8), intent(in)  :: z_r(LBi:UBi,LBj:UBj,N(ng))
      real(r8), intent(in)  :: pden(LBi:UBi,LBj:UBj,N(ng))
      real(r8), intent(in)  :: u(LBi:UBi,LBj:UBj,N(ng),2)
      real(r8), intent(in)  :: v(LBi:UBi,LBj:UBj,N(ng),2)
#  endif
      real(r8), intent(in)  :: ubar(LBi:UBi,LBj:UBj,:)
      real(r8), intent(in)  :: vbar(LBi:UBi,LBj:UBj,:)
      real(r8), intent(in)  :: zeta(LBi:UBi,LBj:UBj,:)

      real(r8), intent(out) :: pvor_bar(LBi:UBi,LBj:UBj)
      real(r8), intent(out) :: rvor_bar(LBi:UBi,LBj:UBj)
#  ifdef SOLVE3D
      real(r8), intent(out) :: pvor(LBi:UBi,LBj:UBj,N(ng))
      real(r8), intent(out) :: rvor(LBi:UBi,LBj:UBj,N(ng))
#  endif
# endif
!
!  Local variable declarations.
!
      integer :: i, j
# ifdef SOLVE3D
      integer :: k, k1, k2
# endif
      real(r8) :: cff
      real(r8) :: dVdx_p, dUde_p, fomn_p
# ifdef SOLVE3D
      real(r8) :: dRde_pr, dRdx_pr, dRdz_pr, dUdz_pr, dVdz_pr
      real(r8) :: orho0

      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dRde
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dRdx
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dUde
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS) :: dVdx

      real(r8), dimension(IminS:ImaxS,JminS:JmaxS,2) :: dRdz
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS,2) :: dUdz
      real(r8), dimension(IminS:ImaxS,JminS:JmaxS,2) :: dVdz
# endif

# include "set_bounds.h"

# ifdef SOLVE3D
!
!-----------------------------------------------------------------------
!  Compute 3D relative and potential vorticity.
!-----------------------------------------------------------------------
!
!  Compute horizontal and vertical gradients.  Notice the recursive
!  blocking sequence for vertical placement of the gradients is:
!
!      dRdz,dUdz,dVdz(:,:,k1) k-1/2   W-points
!      dRdz,dUdz,dVdz(:,:,k2) k+1/2   W-points
!
      orho0=1.0_r8/rho0

      k2=1
      K_LOOP : DO k=0,N(ng)
        k1=k2
        k2=3-k1
        IF (k.gt.0) THEN
          DO j=Jstr-1,JendR
            DO i=Istr,IendR
              cff=0.5_r8*(pm(i,j)+pm(i-1,j))
#  ifdef MASKING
              cff=cff*umask(i,j)
#  endif
              dRdx(i,j)=cff*(pden(i  ,j,k)-                             &
     &                       pden(i-1,j,k))
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr-1,IendR
              cff=0.5_r8*(pn(i,j)+pn(i,j-1))
#  ifdef MASKING
              cff=cff*vmask(i,j)
#  endif
              dRde(i,j)=cff*(pden(i,j  ,k)-                             &
     &                       pden(i,j-1,k))
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr,IendR
              dUde(i,j)=om_u(i,j  )*u(i,j  ,k,nout)-                    &
     &                  om_u(i,j-1)*u(i,j-1,k,nout)
#  ifdef MASKING
              dUde(i,j)=dUde(i,j)*pmask(i,j)
#  endif
              dVdx(i,j)=on_v(i  ,j)*v(i  ,j,k,nout)-                    &
     &                  on_v(i-1,j)*v(i-1,j,k,nout)
#  ifdef MASKING
              dVdx(i,j)=dVdx(i,j)*pmask(i,j)
#  endif
            END DO
          END DO
        END IF
        IF ((k.eq.0).or.(k.eq.N(ng))) THEN
          DO j=Jstr-1,JendR
            DO i=Istr-1,IendR
              dRdz(i,j,k2)=0.0_r8
            END DO
          END DO
          DO j=Jstr-1,JendR
            DO i=Istr,IendR
              dUdz(i,j,k2)=0.0_r8
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr-1,IendR
              dVdz(i,j,k2)=0.0_r8
            END DO
          END DO
        ELSE
          DO j=Jstr-1,JendR
            DO i=Istr-1,IendR
              cff=1.0_r8/(z_r(i,j,k+1)-z_r(i,j,k))
              dRdz(i,j,k2)=cff*(pden(i,j,k+1)-                          &
     &                          pden(i,j,k  ))
            END DO
          END DO
          DO j=Jstr-1,JendR
            DO i=Istr,IendR
              cff=1.0_r8/(0.5_r8*(z_r(i-1,j,k+1)-z_r(i-1,j,k)+          &
     &                            z_r(i  ,j,k+1)-z_r(i  ,j,k)))
              dUdz(i,j,k2)=cff*(u(i,j,k+1,nout)-                        &
     &                          u(i,j,k  ,nout))
            END DO
          END DO
          DO j=Jstr,JendR
            DO i=Istr-1,IendR
              cff=1.0_r8/(0.5_r8*(z_r(i,j-1,k+1)-z_r(i,j-1,k)+          &
     &                            z_r(i,j  ,k+1)-z_r(i,j  ,k)))
              dVdz(i,j,k2)=cff*(v(i,j,k+1,nout)-                        &
     &                          v(i,j,k  ,nout))
            END DO
          END DO
        END IF
!
!  Compute relative vorticity (second-1) and potential vorticity
!  (meter-1 second-1) at horizontal PSI-points and vertical RHO-points.
!
        IF (k.gt.0) THEN
          DO j=Jstr,JendR
            DO i=Istr,IendR
              cff=0.0625_r8*                                            &
     &            (pm(i-1,j-1)+pm(i-1,j)+pm(i,j-1)+pm(i,j))*            &
     &            (pn(i-1,j-1)+pn(i-1,j)+pn(i,j-1)+pn(i,j))
              fomn_p=0.25_r8*(f(i-1,j-1)+f(i-1,j)+f(i,j-1)+f(i,j))/cff
              dRde_pr=dRde(i-1,j  )+dRde(i,j)
              dRdx_pr=dRdx(i  ,j-1)+dRdx(i,j)
              dRdz_pr=0.125_r8*(dRdz(i-1,j-1,k1)+dRdz(i-1,j-1,k2)+      &
     &                          dRdz(i  ,j-1,k1)+dRdz(i  ,j-1,k2)+      &
     &                          dRdz(i-1,j  ,k1)+dRdz(i-1,j  ,k2)+      &
     &                          dRdz(i  ,j  ,k1)+dRdz(i  ,j  ,k2))
              dUdz_pr=dUdz(i  ,j-1,k1)+dUdz(i  ,j-1,k2)+                &
     &                dUdz(i  ,j  ,k1)+dUdz(i  ,j  ,k2)
              dVdz_pr=dVdz(i-1,j  ,k1)+dVdz(i-1,j  ,k2)+                &
     &                dVdz(i  ,j  ,k1)+dVdz(i  ,j  ,k2)
              rvor(i,j,k)=cff*(dVdx(i,j)-dUde(i,j))
              pvor(i,j,k)=orho0*                                        &
     &                    (cff*dRdz_pr*(fomn_p+                         &
     &                                  dVdx(i,j)-dUde(i,j))+           &
     &                     0.125_r8*(dUdz_pr*dRde_pr-dVdz_pr*dRdx_pr))
            END DO
          END DO
        END IF
      END DO K_LOOP
!
!  Exchange boundary data.
!
      IF (EWperiodic(ng).or.NSperiodic(ng)) THEN
        CALL exchange_p3d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj, 1, N(ng),           &
     &                          pvor)
        CALL exchange_p3d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj, 1, N(ng),           &
     &                          rvor)
      END IF

#  ifdef DISTRIBUTE
      CALL mp_exchange3d (ng, tile, iNLM, 2,                            &
     &                    LBi, UBi, LBj, UBj, 1, N(ng),                 &
     &                    NghostPoints, EWperiodic(ng), NSperiodic(ng), &
     &                    pvor,                                         &
     &                    rvor)
#  endif
# endif
!
!-----------------------------------------------------------------------
!  Compute 2D relative and potential vorticity.
!-----------------------------------------------------------------------
!
!  Compute vertically-integrated relative vorticity (second-1) and
!  potential vorticity (meter-1 second-1) at PSI-points.
!
      DO j=Jstr,JendR
        DO i=Istr,IendR
          cff=0.0625_r8*                                                &
     &        (pm(i-1,j-1)+pm(i-1,j)+pm(i,j-1)+pm(i,j))*                &
     &        (pn(i-1,j-1)+pn(i-1,j)+pn(i,j-1)+pn(i,j))
          fomn_p=0.25_r8*(f(i-1,j-1)+f(i-1,j)+f(i,j-1)+f(i,j))/cff
          cff=pm(i,j)*pn(i,j)
          dVdx_p=on_v(i  ,j)*vbar(i  ,j,kout)-                          &
     &           on_v(i-1,j)*vbar(i-1,j,kout)
# ifdef MASKING
          dVdx_p=dVdx_p*pmask(i,j)
# endif
          dUde_p=om_u(i,j  )*ubar(i,j  ,kout)-                          &
     &           om_u(i,j-1)*ubar(i,j-1,kout)
# ifdef MASKING
          dUde_p=dUde_p*pmask(i,j)
# endif
          rvor_bar(i,j)=cff*(dVdx_p-dUde_p)
          pvor_bar(i,j)=cff*((fomn_p+dVdx_p-dUde_p)/                    &
     &                       (h(i,j)+zeta(i,j,kout)))
        END DO
      END DO
!
!  Exchange boundary information.
!
      IF (EWperiodic(ng).or.NSperiodic(ng)) THEN
        CALL exchange_p2d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj,                     &
     &                          pvor_bar)
        CALL exchange_p2d_tile (ng, tile,                               &
     &                          LBi, UBi, LBj, UBj,                     &
     &                          rvor_bar)
      END IF

# ifdef DISTRIBUTE
      CALL mp_exchange2d (ng, tile, iNLM, 2,                            &
     &                    LBi, UBi, LBj, UBj,                           &
     &                    NghostPoints, EWperiodic(ng), NSperiodic(ng), &
     &                    pvor_bar,                                     &
     &                    rvor_bar)
# endif
!
      RETURN
      END SUBROUTINE vorticity_avg_tile
#endif
      END MODULE vorticity_mod
