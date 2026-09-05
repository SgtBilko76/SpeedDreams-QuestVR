/*
 * vr_rtti.cpp - one definition site for the module interface RTTI.
 *
 * Speed Dreams hands modules around as GfModule* and recovers the interface with
 * a dynamic_cast (GfModule::getInterface<>). The interfaces are abstract classes
 * declared in headers only, so every shared library that mentions one emits its
 * own weak copy of the type_info, and libc++'s dynamic_cast compares type_info by
 * address. On the desktop the executable is linked with -Wl,-E and is first in
 * the linker's global scope, so every module binds to that single copy.
 *
 * On Android there is no executable of ours: the core (libsdvr.so) plays that
 * role and is linked with -Wl,-z,global. That is only half the story though - the
 * core has to actually *define* every interface's type_info, otherwise two
 * modules (say standardgame casting the trackv1 loader) each keep their own copy
 * and the cast fails. Referencing them from an exported array does exactly that.
 */

#include <typeinfo>

#include <igraphicsengine.h>
#include <iphysicsengine.h>
#include <iraceengine.h>
#include <isoundengine.h>
#include <itrackloader.h>
#include <iuserinterface.h>

extern "C" const void* const SdVrModuleInterfaceTypeInfo[] = {
    &typeid(IUserInterface),
    &typeid(IRaceEngine),
    &typeid(IGraphicsEngine),
    &typeid(IPhysicsEngine),
    &typeid(ITrackLoader),
    &typeid(ISoundEngine),
    0
};
