
/*
 * Copyright (c) 2020-2020 Apple Inc. All Rights Reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */


#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <getopt.h>
#include <err.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <DiskArbitration/DiskArbitration.h>
#include <DiskArbitration/DiskArbitrationPrivate.h>
#include <paths.h>
#include <time.h>

#define kDAMaxArgLength 2048

struct clarg {
    short present;
    short hasArg;
    char argument[kDAMaxArgLength];
};


enum {
    kDADummy = 0,
    kDADevice,
    kDAMount,
    kDAOptions,
    kDAMountpath,
    kDAUnmount,
    kDAEject,
    kDADiskAppeared,
    kDADiskDisAppeared,
    kDADiskDescChanged,
    kDARename,
    kDAIdle,
    kDASessionKeepAliveWithDAIdle,
    kDASessionKeepAliveWithDADiskAppeared,
    kDASessionKeepAliveWithDARegisterDiskAppeared,
    kDASessionKeepAliveWithDADiskDescriptionChanged,
    kDAForce,
    kDAWhole,
    kDAName,
    kDAUseBlockCallback,
    kDAHelp,
    kDALast
} options;



struct clarg actargs[kDALast];

/*
 * To add an option, allocate an enum in enums.h, add a getopt_long entry here,
 * add to main(), add to usage
 */

/* options descriptor */
static struct option opts[] = {
{ "device",                                     required_argument,      0,              kDADevice},
{ "options",                                    required_argument,      0,              kDAOptions},
{ "mountpath",                                  required_argument,      0,              kDAMountpath},
{ "mount",                                      no_argument,            0,              kDAMount },
{ "unmount",                                    no_argument,            0,              kDAUnmount },
{ "eject",                                      no_argument,            0,              kDAEject },
{ "rename",                                     no_argument,            0,              kDARename },
{ "name",                                       required_argument,      0,              kDAName},
{ "testDiskAppeared",                           no_argument,            0,              kDADiskAppeared },
{ "testDiskDisAppeared",                        no_argument,            0,              kDADiskDisAppeared },
{ "testDiskDescChanged",                        no_argument,            0,              kDADiskDescChanged },
{ "testDAIdle",                                 no_argument,            0,              kDAIdle},
{ "testDASessionKeepAliveWithDAIdle",                  no_argument,            0,              kDASessionKeepAliveWithDAIdle},
{ "testDASessionKeepAliveWithDADiskAppeared",          no_argument,            0,              kDASessionKeepAliveWithDADiskAppeared},
{ "testDASessionKeepAliveWithDARegisterDiskAppeared",  no_argument,            0,              kDASessionKeepAliveWithDARegisterDiskAppeared},
{ "testDASessionKeepAliveWithDADiskDescriptionChanged",no_argument,            0,              kDASessionKeepAliveWithDADiskDescriptionChanged},
{ "force",                                      no_argument,            0,              kDAForce},
{ "whole",                                      no_argument,            0,              kDAWhole},
{ "useBlockCallback",                           no_argument,            0,              kDAUseBlockCallback},
{ "help",                                       no_argument,            0,              kDAHelp },
{ 0,                   0,                      0,              0 }
};


extern char *optarg;
extern int optind;
dispatch_queue_t myDispatchQueue;
int done = 0;
static void usage(void)
{
    fprintf(stderr, "Usage: %s [options]\n", getprogname());
    fputs(
"datest --help\n"
"\n"
"datest --mount --device <device> [--options <options> ] [--mountpath <path>] [--useBlockCallback] \n"
"datest --unmount --device <device> [--force ] [--whole ] [--useBlockCallback] \n"
"datest --eject --device <device> [--useBlockCallback] \n"
"datest --rename --device <device>  --name <name> [--useBlockCallback] \n"
"datest --testDiskAppeared [--useBlockCallback] \n"
"datest --testDiskDisAppeared --device <device> [--useBlockCallback] \n"
"datest --testDiskDescChanged --device <device> [--useBlockCallback] \n"
"datest --testDAIdle  [--useBlockCallback] \n"
#if !TARGET_OS_OSX
"datest --testDASessionKeepAliveWithDAIdle  \n"
"datest --testDASessionKeepAliveWithDADiskAppeared  \n"
"datest --testDASessionKeepAliveWithDARegisterDiskAppeared  \n"
"datest --testDASessionKeepAliveWithDADiskDescriptionChanged \n"
#endif
"\n"
,
      stderr);
    exit(1);
}

static int TranslateDAError( DAReturn errnum )
{
    int    ret;

    if (errnum >= unix_err(0) && errnum <= unix_err(ELAST)) {
        ret = errnum & ~unix_err(0);
    } else {
        ret = errnum;
    }
    return ret;
}


static int validateArguments( int validArgs[], int numOfRequiredArgs, struct clarg actargs[kDALast] )
{
    for (int i =0; i < numOfRequiredArgs; i++)
    {
        if (0 == actargs[validArgs[i]].present){
            usage();
            return 1;
        }
    }
    return 0;
}

void DiskMountCallback( DADiskRef disk, DADissenterRef dissenter, void **context )
{
    
    DAReturn    ret = 0;
    if (dissenter) {
        ret = DADissenterGetStatus(dissenter);
    }
    printf("mount finished with return status %0x \n", TranslateDAError(ret));
    *(OSStatus *)context = TranslateDAError(ret);
    done = 1;
}


void DiskUnmountCallback ( DADiskRef disk, DADissenterRef dissenter, void ** context )
{
    DAReturn    ret = 0;
    if (dissenter) {
        ret = DADissenterGetStatus(dissenter);
    }
    printf("unmount finished with return status %0x \n", TranslateDAError(ret));
    *(OSStatus *)context = TranslateDAError(ret);
    done = 1;
}

void DiskRenameCallback ( DADiskRef disk, DADissenterRef dissenter, void ** context )
{
    DAReturn    ret = 0;
    if (dissenter) {
        ret = DADissenterGetStatus(dissenter);
    }
    printf("Rename finished with return status %0x \n", TranslateDAError(ret));
    *(OSStatus *)context = TranslateDAError(ret);
    done = 1;
}

 void DiskEjectCallback( DADiskRef disk, DADissenterRef dissenter, void **context )
{

     DAReturn    ret = 0;
     if (dissenter) {
         ret = DADissenterGetStatus(dissenter);
     }
     printf("eject finished with return status %0x \n", TranslateDAError(ret));
     *(OSStatus *)context = TranslateDAError(ret);
     done = 1;
  
}

static void
DiskAppearedCallback( DADiskRef disk, void *context )
{
    printf("DiskAppearedCallback dispatched\n");
    done = 1;
}

static void
DiskDisAppearedCallback( DADiskRef disk, void *context )
{
    printf("DiskDisAppearedCallback dispatched\n");
    done = 1;
}

void DiskDescriptionChangedCallback( DADiskRef disk, CFArrayRef keys, void *context )
{
    CFRetain(disk);
    CFShow(disk);
    CFShow(keys);
    printf("DiskDescriptionChangedCallback dispatched\n");
    done = 1;
}

void IdleCallback(void *context)
{
    printf("Idle received\n");
    done = 1;
}

bool WaitForCallback()
{
    bool cbdispatched = true;
    time_t start_t, end_t;
    start_t = time(NULL);
    end_t = start_t + 15;
    do {
        sleep(1);
        start_t = time(NULL);
        if ( start_t > end_t )
        {
            cbdispatched = false;
            break;
        }
    } while  ( !done );

    return cbdispatched;
}

pid_t pgrep(const char* proc_name)
{
    pid_t ret = 0;
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "pgrep -x %s", proc_name);
    FILE *f = popen(cmd, "r");
    if (!f) {
        printf("pgrep failed: %d (%s)", errno, strerror(errno));
        return 0;
    }
    char pid_str[256];
    if (fgets(pid_str, sizeof(pid_str), f)) {
        ret = (pid_t)strtoul(pid_str, NULL, 10);
    }
    pclose(f);
    return ret;
}

static int testMount(struct clarg actargs[kDALast])
{
    OSStatus                     ret = 1;
    DASessionRef            _session = DASessionCreate(kCFAllocatorDefault);
    int                     validArgs[] = {kDADevice};
    CFURLRef                mountpoint = NULL;
    CFStringRef             *mountoptions = NULL;
    
    if (validateArguments(validArgs, sizeof(validArgs)/sizeof(int), actargs))
    {
        goto exit;
    }
    
    DADiskRef _disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, actargs[kDADevice].argument);

  
    if (!_disk)      {
        printf( "%s does not exist.\n", actargs[kDADevice].argument);
        goto exit;
    }
        
    if (DADiskCopyDescription(_disk) == NULL)
    {
        printf( "DADiskCopyDescription failed.\n ");
        goto exit;
    }
    
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {
      
        mountpoint = CFURLCreateFromFileSystemRepresentation( kCFAllocatorDefault, ( void * ) actargs[kDAMountpath].argument, strlen( actargs[kDAMountpath].argument ), TRUE );
        if (actargs[kDAOptions].present)
        {
            mountoptions = calloc(2, sizeof(void *));
            mountoptions[0] = CFStringCreateWithCString(kCFAllocatorDefault, actargs[kDAOptions].argument, kCFStringEncodingUTF8);
        }
        int options = kDADiskUnmountOptionDefault;
            
        if (actargs[kDAWhole].present) {
            options |= kDADiskUnmountOptionWhole;
        }
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskMountCallbackBlock block = ^( DADiskRef disk, DADissenterRef dissenter )
            {
                DiskMountCallback( disk, dissenter, &ret);
            };
            DADiskMountWithArgumentsAndBlock( _disk, mountpoint, options, block, mountoptions );
        }
        else
        {
            DADiskMountWithArguments (_disk, mountpoint, options, DiskMountCallback, &ret, mountoptions);
        }
        
        ret = 0;
    }

    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    if (mountoptions) free(mountoptions);
    return ret;
}

static int testUnmount(struct clarg actargs[kDALast])
{
    OSStatus                     ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
    int                     validArgs[] = {kDADevice};
    
    if (validateArguments(validArgs, sizeof(validArgs)/sizeof(int), actargs))
    {
        goto exit;
    }
    DADiskRef _disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, actargs[kDADevice].argument);
  
    if (!_disk)      {
        printf( "%s does not exist", actargs[kDADevice].argument);
        goto exit;
    }
        
    if (DADiskCopyDescription(_disk) == NULL)
    {
        printf( "DADiskCopyDescription failed.\n ");
        goto exit;
    }
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        int options = kDADiskUnmountOptionDefault;
        if (actargs[kDAForce].present) {
            options |= kDADiskUnmountOptionForce;
        }
            
        if (actargs[kDAWhole].present) {
            options |= kDADiskUnmountOptionWhole;
        }
        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskUnmountCallbackBlock block = ^( DADiskRef disk, DADissenterRef dissenter  )
            {
                DiskUnmountCallback( disk, dissenter, &ret );
            };
        
            DADiskUnmountWithBlock( _disk, options, block );
        }
        else
        {
            DADiskUnmount( _disk, options, DiskUnmountCallback,  &ret );
        }
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    return ret;
}

static int testEject(struct clarg actargs[kDALast])
{
    OSStatus                     ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
    int                     validArgs[] = {kDADevice};
    CFDictionaryRef     description = NULL;
    
    if (validateArguments(validArgs, sizeof(validArgs)/sizeof(int), actargs))
    {
        goto exit;
    }
    DADiskRef _disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, actargs[kDADevice].argument);
  
    if (!_disk)      {
        printf( "%s does not exist", actargs[kDADevice].argument);
        goto exit;
    }
        
    description = DADiskCopyDescription(_disk);
    if (description) {
            
        if ( CFDictionaryGetValue( description, kDADiskDescriptionMediaWholeKey ) == NULL ||
            CFDictionaryGetValue( description, kDADiskDescriptionMediaWholeKey ) == kCFBooleanFalse)
        {
            printf( "%s is not a whole device.\n ", actargs[kDADevice].argument);
            goto exit;
        }
    }
    else
    {
        printf( "DADiskCopyDescription failed.\n ");
        goto exit;
    }
    
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        int options = kDADiskUnmountOptionDefault;
        
        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskEjectCallbackBlock block = ^( DADiskRef disk, DADissenterRef dissenter )
            {
                DiskEjectCallback( disk, dissenter, &ret);
            };
            DADiskEjectWithBlock( _disk,
                            options,
                            block );

        }
        else
        {
            DADiskEject( _disk,
                        options,
                        DiskEjectCallback,
                        &ret );
        }
        
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    return ret;
}


static int testDiskAppeared(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
    
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskAppearedCallbackBlock block =  ^( DADiskRef disk )
            {
                DiskAppearedCallback( disk, &ret);
            };
            DARegisterDiskAppearedCallbackBlock(_session, NULL, block );
        }
       else
       {
           DARegisterDiskAppearedCallback(_session, NULL, DiskAppearedCallback, &ret);
       }
    
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    return ret;
}

static int testDiskDisAppeared(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
    int                     validArgs[] = {kDADevice};
    CFDictionaryRef     description = NULL;
        
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if (validateArguments(validArgs, sizeof(validArgs)/sizeof(int), actargs))
    {
        goto exit;
    }
    DADiskRef _disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, actargs[kDADevice].argument);
  
    if (!_disk)      {
        printf( "%s does not exist", actargs[kDADevice].argument);
        goto exit;
    }
    
    description = DADiskCopyDescription(_disk);
    if (description) {
            
        if ( CFDictionaryGetValue( description, kDADiskDescriptionMediaWholeKey ) == NULL ||
            CFDictionaryGetValue( description, kDADiskDescriptionMediaWholeKey ) == kCFBooleanFalse)
        {
            printf( "%s is not a whole device.\n ", actargs[kDADevice].argument);
            goto exit;
        }
    }
    else
    {
        printf( "DADiskCopyDescription failed.\n ");
        goto exit;
    }
    if ( _session ) {

        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskDisappearedCallbackBlock block =  ^( DADiskRef disk )
            {
                DiskDisAppearedCallback( disk, &ret);
            };
            DARegisterDiskDisappearedCallbackBlock(_session, NULL, block );
        }
        else
        {
            DARegisterDiskDisappearedCallback(_session, NULL, DiskDisAppearedCallback, &ret);
        }
        DADiskEject( _disk,
                     kDADiskUnmountOptionDefault,
                     NULL,
                     NULL );
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
            printf( "Eject failed. Check if any of the volumes are mounted.\n ");
        }
    }

exit:
    return ret;
}


static int testDiskDescriptionChanged(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
    int                     validArgs[] = {kDADevice};
    CFDictionaryRef     description = NULL;
    
    if (validateArguments(validArgs, sizeof(validArgs)/sizeof(int), actargs))
    {
        goto exit;
    }
    DADiskRef _disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, actargs[kDADevice].argument);
  
    if (!_disk)      {
        printf( "%s does not exist", actargs[kDADevice].argument);
        goto exit;
    }
    
    description = DADiskCopyDescription(_disk);
    if (description) {
            
        if ( CFDictionaryGetValue(description, kDADiskDescriptionVolumePathKey) == NULL )
        {
            printf( "volume is not mounted. mount the volume and try again.\n ");
            goto exit;
        }
    }
    else
    {
        printf( "DADiskCopyDescription failed.\n ");
        goto exit;
    }
        
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskDescriptionChangedCallbackBlock block =  ^( DADiskRef disk, CFArrayRef keys )
            {
                DiskDescriptionChangedCallback( disk, keys, &ret);
            };
            DARegisterDiskDescriptionChangedCallbackBlock(_session, NULL, NULL, block );
        }
        else
        {
            DARegisterDiskDescriptionChangedCallback(_session, NULL, NULL, DiskDescriptionChangedCallback, &ret);
        }

        DADiskUnmount( _disk,
                           kDADiskUnmountOptionDefault,
                           NULL,
                           NULL );
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    return ret;
}

static int testDAIdle(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
  
    DAIdleCallbackBlock block;
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        if ( actargs[kDAUseBlockCallback].present )
        {
            DAIdleCallbackBlock block =  ^( void )
            {
                IdleCallback( NULL );
            };
            DARegisterIdleCallbackWithBlock(_session, block );
        }
        else
        {
            DARegisterIdleCallback(_session, IdleCallback, NULL);
        }
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    if (ret == 0)
    {
        DAUnregisterCallback(_session, (void *) block, NULL);
    }
    
    return ret;
}

static int testRename(struct clarg actargs[kDALast])
{
    OSStatus                     ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
    int                     validArgs[] = {kDADevice, kDAName};
    CFDictionaryRef     description = NULL;
    
    if (validateArguments(validArgs, sizeof(validArgs)/sizeof(int), actargs))
    {
        goto exit;
    }
    DADiskRef _disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, actargs[kDADevice].argument);
  
    if (!_disk)      {
        printf( "%s does not exist", actargs[kDADevice].argument);
        goto exit;
    }
        
    description = DADiskCopyDescription(_disk);
    if (description) {
            
        if ( CFDictionaryGetValue(description, kDADiskDescriptionVolumePathKey) == NULL )
        {
            printf( "volume is not mounted. mount the volume and try again.\n ");
            goto exit;
        }
    }
    else
    {
        printf( "DADiskCopyDescription failed.\n ");
        goto exit;
    }
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault,actargs[kDAName].argument, kCFStringEncodingUTF8);
        if ( actargs[kDAUseBlockCallback].present )
        {
            DADiskRenameCallbackBlock block =  ^( DADiskRef disk, DADissenterRef dissenter )
            {
                DiskRenameCallback( disk, dissenter, &ret );
            };
            DADiskRenameWithBlock(_disk, name, NULL, block );
        }
        else
        {
            DADiskRename(_disk, name, NULL, DiskRenameCallback, &ret);        }
        
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
        }
    }

exit:
    return ret;
}
#if !TARGET_OS_OSX

static int WaitForDADaemonExit()
{
    time_t end_t;
    pid_t pid = 0;

    end_t = time(NULL) + 32;
    do {
        sleep(1);
        pid = pgrep("diskarbitrationd");
        if ( time(NULL) > end_t )
            break;
    } while ( pid != 0 );

    if ( pid != 0 ) {
        printf ("diskarbitrationd is still running\n");
        return -1;
    } else {
        printf ("diskarbitrationd exited. Expect to receive callbacks\n");
        return 0;
    }
}

static int testDASessionKeepAliveWithDAIdle(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
  
        
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        DARegisterIdleCallback(_session, IdleCallback, NULL);
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        DASessionKeepAlive( _session, myDispatchQueue);
        printf ("set the current session to be kept alive across daemon launches\n");
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
            goto exit;
        }
    }
 
    // wait for DA to exit
    if ((ret = WaitForDADaemonExit()) != 0)
    {
        goto exit;
    }
  
    printf ("Attach an external drive or run datest from another terminal\n");
    done = 0;
    if ( WaitForCallback() == false )
    {
        printf ("Failed to receive callbacks from diskarbitrationd\n");
        ret = -1;
    }
exit:
    return ret;
}

static int testDASessionKeepAliveWithDADiskAppeared(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
  
        
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        DARegisterDiskAppearedCallback(_session, NULL, DiskAppearedCallback, &ret);
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        DASessionKeepAlive( _session, myDispatchQueue);
        printf ("set the current session to be kept alive across daemon launches\n");
        ret = 0;
    }
    
    if ( ret == 0 )
    {
        if ( WaitForCallback() == false )
        {
            ret = -1;
            goto exit;
        }
    }
 
    // wait for DA to exit
    if ((ret = WaitForDADaemonExit()) != 0)
    {
        goto exit;
    }
    
    printf ("Attach an external drive or run datest from another terminal\n");

    done = 0;
    if ( WaitForCallback() == false )
    {
        printf ("Failed to receive callbacks from diskarbitrationd\n");
        ret = -1;
    }
exit:
    return ret;
}

static int testDASessionKeepAliveWithDADiskDescriptionChanged(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
  
        
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        DARegisterDiskDescriptionChangedCallback(_session, NULL, NULL, DiskDescriptionChangedCallback, &ret);
        DASessionSetDispatchQueue(_session, myDispatchQueue);
        DASessionKeepAlive( _session, myDispatchQueue);
        printf ("set the current session to be kept alive across daemon launches\n");
        ret = 0;
    }
 
    // wait for DA to exit
    if ((ret = WaitForDADaemonExit()) != 0)
    {
        goto exit;
    }
    
    printf ("run datest --mount from another terminal\n");

    done = 0;

    if ( WaitForCallback() == false )
    {
        printf ("Failed to receive callbacks from diskarbitrationd\n");
        ret = -1;
    }
exit:
    return ret;
}

static int testDASessionKeepAliveWithDARegisterDiskAppeared(struct clarg actargs[kDALast])
{
    int             ret = 1;
    DASessionRef _session = DASessionCreate(kCFAllocatorDefault);
  
        
    myDispatchQueue = dispatch_queue_create("com.example.DiskArbTest", DISPATCH_QUEUE_SERIAL);
    
    if ( _session ) {

        DASessionSetDispatchQueue(_session, myDispatchQueue);
        DASessionKeepAlive( _session, myDispatchQueue);
        printf ("set the current session to be kept alive across daemon launches\n");
        ret = 0;
    }
 
    // wait for DA to exit
    sleep ( 30 );
    pid_t pid = pgrep("diskarbitrationd");
    if ( pid != 0 )
    {
        printf ("diskarbitrationd is still running\n");
        ret = -1;
        goto exit;
    }
    else
    {
        printf ("diskarbitrationd exited. Expect to receive callbacks\n");
    }
    
    DARegisterDiskAppearedCallback(_session, NULL, DiskAppearedCallback, &ret);
    done = 0;
    if ( WaitForCallback() == false )
    {
        printf ("Failed to receive callbacks from diskarbitrationd\n");
        ret = -1;
    }
exit:
    return ret;
}
#endif


int main (int argc, char * argv[])
{

    int ch, longindex;

    setlinebuf(stdout);
    
    if(argc == 1) {
        usage();
    }
    
    
    while ((ch = getopt_long_only(argc, argv, "", opts, &longindex)) != -1) {
        
        switch(ch) {
            case kDAHelp:
                usage();
                break;
            case '?':
            case ':':
                usage();
                break;
            default:
                // common handling for all other options
            {
                struct option *opt = &opts[longindex];
                
                if(actargs[ch].present) {
                    warnx("Option \"%s\" already specified", opt->name);
                    usage();
                    break;
                } else {
                    actargs[ch].present = 1;
                }
                
                switch(opt->has_arg) {
                    case no_argument:
                        actargs[ch].hasArg = 0;
                        break;
                    case required_argument:
                        actargs[ch].hasArg = 1;
                        strlcpy(actargs[ch].argument, optarg, sizeof(actargs[ch].argument));
                        break;
                    case optional_argument:
                        if(argv[optind] && argv[optind][0] != '-') {
                            actargs[ch].hasArg = 1;
                            strlcpy(actargs[ch].argument, argv[optind], sizeof(actargs[ch].argument));
                        } else {
                            actargs[ch].hasArg = 0;
                        }
                        break;
                }
            }
                break;
        }
    }

    argc -= optind;
    argc += optind;
    
    if(actargs[kDAMount].present) {
        return testMount(actargs);
    }

    if(actargs[kDAUnmount].present) {
        return testUnmount(actargs);
    }
    
    if(actargs[kDAEject].present) {
        return testEject(actargs);
    }
   
    if(actargs[kDARename].present) {
        return testRename(actargs);
    }
    
    if(actargs[kDADiskAppeared].present) {
        return testDiskAppeared(actargs);
    }

    if(actargs[kDADiskDisAppeared].present) {
        return testDiskDisAppeared(actargs);
    }
    
    if(actargs[kDADiskDescChanged].present) {
        return testDiskDescriptionChanged(actargs);
    }
    
    if(actargs[kDAIdle].present) {
        return testDAIdle(actargs);
    }
    
#if !TARGET_OS_OSX
    if(actargs[kDASessionKeepAliveWithDAIdle].present) {
        return testDASessionKeepAliveWithDAIdle(actargs);
    }
    if(actargs[kDASessionKeepAliveWithDADiskAppeared].present) {
        return testDASessionKeepAliveWithDADiskAppeared(actargs);
    }
    if(actargs[kDASessionKeepAliveWithDARegisterDiskAppeared].present) {
        return testDASessionKeepAliveWithDARegisterDiskAppeared(actargs);
    }
    if(actargs[kDASessionKeepAliveWithDADiskDescriptionChanged].present) {
        return testDASessionKeepAliveWithDADiskDescriptionChanged(actargs);
    }
#endif
    /* default */
    return 0;
}
