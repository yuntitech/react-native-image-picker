//
//  NonAutorotateImagePickerViewController.m
//  react-native-image-picker
//
//  Created by leejunhui on 2020/11/12.
//

#import "NonAutorotateImagePickerViewController.h"

@interface NonAutorotateImagePickerViewController ()

@end

@implementation NonAutorotateImagePickerViewController

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscape;
}

@end
