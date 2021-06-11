#import "ImagePickerManager.h"
#import <React/RCTConvert.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <React/RCTUtils.h>
#import "NonAutorotateImagePickerViewController.h"
@import MobileCoreServices;
@interface ImagePickerManager () <UIPopoverPresentationControllerDelegate
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
, UIAdaptivePresentationControllerDelegate
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000 // Xcode 12 and iOS 14, or greater
, PHPickerViewControllerDelegate
#endif
>
@property (nonatomic, strong) RCTResponseSenderBlock callback;
@property (nonatomic, strong) NSDictionary *defaultOptions;
@property (nonatomic, retain) NSMutableDictionary *options, *response;
@property (nonatomic, strong) NSArray *customButtons;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
@property (nonatomic, strong) PHPickerViewController *phPicker;
#endif
@property (nonatomic, assign) BOOL isPhotoLibraryLimitedAccess;
@end

@implementation ImagePickerManager

static UIImagePickerController *imagePicker = nil;

+ (UIImagePickerController *)sharedImagePickerController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imagePicker = [[NonAutorotateImagePickerViewController alloc] init];
    });
    return imagePicker;
}


#pragma mark - RN Related
RCT_EXPORT_MODULE();

#pragma mark RN Method 打开相机
/**
 打开相机
 */
RCT_EXPORT_METHOD(launchCamera:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback;
    if (@available(iOS 14, *)) {
        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
        [self launchPhotoKitImagePicker:RNImagePickerTargetCamera options:options];
        #endif
    } else {
        [self launchImagePicker:RNImagePickerTargetCamera options:options];
    }
}

#pragma mark RN Method 打开相册
/**
 打开相册
 */
RCT_EXPORT_METHOD(launchImageLibrary:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback;
    if (@available(iOS 14, *)) {
        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
        [self launchPhotoKitImagePicker:RNImagePickerTargetLibrarySingleImage options:options];
        #endif
    } else {
        [self launchImagePicker:RNImagePickerTargetLibrarySingleImage options:options];
    }
}

#pragma mark RN Method 弹出照片选择器
/**
 弹出照片选择器
 */
RCT_EXPORT_METHOD(showImagePicker:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback; // Save the callback so we can use it from the delegate methods
    self.options = [options mutableCopy];
    
    NSString *title = [self.options valueForKey:@"title"];
    if ([title isEqual:[NSNull null]] || title.length == 0) {
        title = nil; // A more visually appealing UIAlertControl is displayed with a nil title rather than title = @""
    }
    NSString *cancelTitle = [self.options valueForKey:@"cancelButtonTitle"];
    NSString *takePhotoButtonTitle = [self.options valueForKey:@"takePhotoButtonTitle"];
    NSString *chooseFromLibraryButtonTitle = [self.options valueForKey:@"chooseFromLibraryButtonTitle"];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        self.callback(@[@{@"didCancel": @YES}]); // Return callback for 'cancel' action (if is required)
    }];
    [alertController addAction:cancelAction];
    
    if (![takePhotoButtonTitle isEqual:[NSNull null]] && takePhotoButtonTitle.length > 0) {
        UIAlertAction *takePhotoAction = [UIAlertAction actionWithTitle:takePhotoButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            [self actionHandler:action];
        }];
        [alertController addAction:takePhotoAction];
    }
    if (![chooseFromLibraryButtonTitle isEqual:[NSNull null]] && chooseFromLibraryButtonTitle.length > 0) {
        UIAlertAction *chooseFromLibraryAction = [UIAlertAction actionWithTitle:chooseFromLibraryButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            [self actionHandler:action];
        }];
        [alertController addAction:chooseFromLibraryAction];
    }
    
    // Add custom buttons to action sheet
    if ([self.options objectForKey:@"customButtons"] && [[self.options objectForKey:@"customButtons"] isKindOfClass:[NSArray class]]) {
        self.customButtons = [self.options objectForKey:@"customButtons"];
        for (NSString *button in self.customButtons) {
            NSString *title = [button valueForKey:@"title"];
            UIAlertAction *customAction = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                [self actionHandler:action];
            }];
            [alertController addAction:customAction];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = RCTPresentedViewController();
        
        /* On iPad, UIAlertController presents a popover view rather than an action sheet like on iPhone. We must provide the location
         of the location to show the popover in this case. For simplicity, we'll just display it on the bottom center of the screen
         to mimic an action sheet */
        alertController.popoverPresentationController.sourceView = root.view;
        alertController.popoverPresentationController.sourceRect = CGRectMake(root.view.bounds.size.width / 2.0, root.view.bounds.size.height, 1.0, 1.0);
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            alertController.popoverPresentationController.permittedArrowDirections = 0;
            if (!alertController.popoverPresentationController.delegate) {
                alertController.popoverPresentationController.delegate = self;
            }
            for (id subview in alertController.view.subviews) {
                if ([subview isMemberOfClass:[UIView class]]) {
                    ((UIView *)subview).backgroundColor = [UIColor whiteColor];
                }
            }
        }
        
        [root presentViewController:alertController animated:YES completion:nil];
    });
}

/**
 集中处理 UIActionAlertController 事件
 */
- (void)actionHandler:(UIAlertAction *)action
{
    // If button title is one of the keys in the customButtons dictionary return the value as a callback
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title==%@", action.title];
    NSArray *results = [self.customButtons filteredArrayUsingPredicate:predicate];
    if (results.count > 0) {
        NSString *customButtonStr = [[results objectAtIndex:0] objectForKey:@"name"];
        if (customButtonStr) {
            self.callback(@[@{@"customButton": customButtonStr}]);
            return;
        }
    }
    
    if ([action.title isEqualToString:[self.options valueForKey:@"takePhotoButtonTitle"]]) {
        // Take photo
        [self launchImagePicker:RNImagePickerTargetCamera];
    }
    else if ([action.title isEqualToString:[self.options valueForKey:@"chooseFromLibraryButtonTitle"]]) {
        // Choose from library
        if (@available(iOS 14, *)) {
            #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
            [self launchPhotoKitImagePicker:RNImagePickerTargetLibrarySingleImage];
            #endif
        } else {
            [self launchImagePicker:RNImagePickerTargetLibrarySingleImage];
        }
    }
}

#pragma mark - iOS 14 适配 / PhotoKit
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
- (void)launchPhotoKitImagePicker:(RNImagePickerTarget)target options:(NSDictionary *)options API_AVAILABLE(ios(14.0));
{
    self.options = [options mutableCopy];
    [self launchPhotoKitImagePicker:target];
}

- (void)launchPhotoKitImagePicker:(RNImagePickerTarget)target API_AVAILABLE(ios(14.0));
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (target == RNImagePickerTargetCamera) {
            [self startLaunchImagePicker:target];
        } else {
            [self startLaunchPhotoKitImagePicker:target];
        }
    });
}

- (void)startLaunchPhotoKitImagePicker:(RNImagePickerTarget)target API_AVAILABLE(ios(14.0));
{
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    
    // 由于 iOS14 推出的 PHPickerViewController 只是替换了原有的 UIImagePickerController 中选择图片的功能
    // 而对于拍照，还是会使用到 UIImagePickerController
    if (target == RNImagePickerTargetCamera) {
        
#if TARGET_IPHONE_SIMULATOR
        self.callback(@[@{@"error": @"Camera not available on simulator"}]);
        return;
#else
        [ImagePickerManager sharedImagePickerController].sourceType = UIImagePickerControllerSourceTypeCamera;
        if ([[self.options objectForKey:@"cameraType"] isEqualToString:@"front"]) {
            [ImagePickerManager sharedImagePickerController].cameraDevice = UIImagePickerControllerCameraDeviceFront;
        }
        else { // "back"
            [ImagePickerManager sharedImagePickerController].cameraDevice = UIImagePickerControllerCameraDeviceRear;
        }
#endif
    }
    
    // 如果 options 中包含 mediaType 的 key 的 value 为 video 或 mixed
    if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"video"]
        || [[self.options objectForKey:@"mediaType"] isEqualToString:@"mixed"]) {
        
        // videoQuality 高质量
        if ([[self.options objectForKey:@"videoQuality"] isEqualToString:@"high"]) {
            [ImagePickerManager sharedImagePickerController].videoQuality = UIImagePickerControllerQualityTypeHigh;
        }
        // videoQuality 低质量
        else if ([[self.options objectForKey:@"videoQuality"] isEqualToString:@"low"]) {
            [ImagePickerManager sharedImagePickerController].videoQuality = UIImagePickerControllerQualityTypeLow;
        }
        // videoQuality 中质量
        else {
            [ImagePickerManager sharedImagePickerController].videoQuality = UIImagePickerControllerQualityTypeMedium;
        }
        
        // 时长限制
        id durationLimit = [self.options objectForKey:@"durationLimit"];
        if (durationLimit) {
            [ImagePickerManager sharedImagePickerController].videoMaximumDuration = [durationLimit doubleValue];
            [ImagePickerManager sharedImagePickerController].allowsEditing = NO;
        }
    }
    
    if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"video"]) {
        configuration.filter = PHPickerFilter.videosFilter;
        [ImagePickerManager sharedImagePickerController].mediaTypes = @[(NSString *)kUTTypeMovie];
    } else if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"mixed"]) {
        [ImagePickerManager sharedImagePickerController].mediaTypes = @[(NSString *)kUTTypeMovie, (NSString *)kUTTypeImage];
    } else {
        configuration.filter = PHPickerFilter.imagesFilter;
        [ImagePickerManager sharedImagePickerController].mediaTypes = @[(NSString *)kUTTypeImage];
    }
    

    self.phPicker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    self.phPicker.delegate = self;
    // 设置 PresentationDelegate 为当前对象，方便监听用户下滑 dismiss 掉 PHPicker 事件
    self.phPicker.presentationController.delegate = self;
    self.phPicker.modalPresentationStyle = UIModalPresentationFullScreen;
    
    if ([[self.options objectForKey:@"allowsEditing"] boolValue]) {
        [ImagePickerManager sharedImagePickerController].allowsEditing = true;
    }
    [ImagePickerManager sharedImagePickerController].modalPresentationStyle = UIModalPresentationFullScreen;
    [ImagePickerManager sharedImagePickerController].delegate = self;
    
    // Check permissions
    void (^showPickerViewController)(void) = ^void() {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *root = RCTPresentedViewController();
            [root presentViewController:[ImagePickerManager sharedImagePickerController] animated:YES completion:nil];
        });
    };
    
    void (^showPHPickerViewController)(void) = ^void() {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *root = RCTPresentedViewController();
            [root presentViewController:self.phPicker animated:YES completion:nil];
        });
    };
    
    // 检查相机权限
    if (target == RNImagePickerTargetCamera) {
        [self checkCameraPermissions:^(BOOL granted) {
            if (!granted) {
                self.callback(@[@{@"error": @"Camera permissions not granted"}]);
                return;
            }
            
            showPickerViewController();
        }];
    } else {
        __weak typeof(self) weakSelf = self;
        [self checkPhotosPermissions:^(BOOL granted) {
            __strong typeof(self) strongSelf = weakSelf;
            if (!granted) {
                strongSelf.callback(@[@{@"error": @"Photo library permissions not granted"}]);
                return;
            }
            showPHPickerViewController();
//            if (strongSelf.isPhotoLibraryLimitedAccess) {
//                [[PHPhotoLibrary sharedPhotoLibrary] presentLimitedLibraryPickerFromViewController:RCTPresentedViewController()];
//            } else {
//                showPHPickerViewController();
//            }
        }];
    }
}

#pragma mark PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0));
{
    __block NSString *fileName;
    
    /**
     通过 PhotoAsset 获取 URL 的完成回调
     */
    void (^photoAssetImageEditingInputCompletionHandler)(PHContentEditingInput *editingInput, UIImage *image, PHAsset *pickedAsset) = ^(PHContentEditingInput *editingInput, UIImage *image, PHAsset *pickedAsset){
        if (editingInput == nil) return;
        
        NSURL *imageURL = editingInput.fullSizeImageURL;
        
        NSString *tempFileName = [[NSUUID UUID] UUIDString];
        if (imageURL && [[imageURL absoluteString] rangeOfString:@"GIF"].location != NSNotFound) {
            fileName = [tempFileName stringByAppendingString:@".gif"];
        }
        else if ([[[self.options objectForKey:@"imageFileType"] stringValue] isEqualToString:@"png"]) {
            fileName = [tempFileName stringByAppendingString:@".png"];
        }
        else {
            fileName = [tempFileName stringByAppendingString:@".jpg"];
        }
        
        
        // We default to path to the temporary directory
        NSString *path = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:fileName];
        
        // If storage options are provided, we use the documents directory which is persisted
        if ([self.options objectForKey:@"storageOptions"] && [[self.options objectForKey:@"storageOptions"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *storageOptions = [self.options objectForKey:@"storageOptions"];
            
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            path = [documentsDirectory stringByAppendingPathComponent:fileName];
            
            // Creates documents subdirectory, if provided
            if ([storageOptions objectForKey:@"path"]) {
                NSString *newPath = [documentsDirectory stringByAppendingPathComponent:[storageOptions objectForKey:@"path"]];
                NSError *error;
                [[NSFileManager defaultManager] createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:&error];
                if (error) {
                    NSLog(@"Error creating documents subdirectory: %@", error);
                    self.callback(@[@{@"error": error.localizedFailureReason}]);
                    return;
                }
                else {
                    path = [newPath stringByAppendingPathComponent:fileName];
                }
            }
        }
        
        // Create the response object
        self.response = [[NSMutableDictionary alloc] init];
        
        NSString *originalFilename = [self originalFilenameForAsset:pickedAsset assetType:PHAssetResourceTypePhoto];
        self.response[@"fileName"] = originalFilename ?: [NSNull null];
        if (pickedAsset.location) {
            self.response[@"latitude"] = @(pickedAsset.location.coordinate.latitude);
            self.response[@"longitude"] = @(pickedAsset.location.coordinate.longitude);
        }
        if (pickedAsset.creationDate) {
            self.response[@"timestamp"] = [[ImagePickerManager ISO8601DateFormatter] stringFromDate:pickedAsset.creationDate];
        }
        
        __block BOOL isGif = NO;
        
        // Gif 特殊处理
        if (imageURL && [[imageURL absoluteString] rangeOfString:@"GIF"].location != NSNotFound) {
            PHImageRequestOptions *options = [PHImageRequestOptions new];
            options.resizeMode = PHImageRequestOptionsResizeModeFast;
            options.synchronous = YES;
            
            // 初始化 PHImageManager
            PHImageManager *imageManager = [[PHImageManager alloc] init];
            [imageManager requestImageDataAndOrientationForAsset:pickedAsset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
                isGif = YES;
                if (info[PHImageErrorKey] != nil) {
                    NSError *error = info[PHImageErrorKey];
                    self.callback(@[@{@"error": error.localizedFailureReason}]);
                    return;
                }
                
                // 通过 PHImageManager 拿到 Gif 图片的 二进制数据，然后写入到缓存中
                [imageData writeToFile:path atomically:YES];
                
                NSMutableDictionary *gifResponse = [[NSMutableDictionary alloc] init];
                [gifResponse setObject:@(image.size.width) forKey:@"width"];
                [gifResponse setObject:@(image.size.height) forKey:@"height"];
                
                BOOL vertical = (image.size.width < image.size.height) ? YES : NO;
                [gifResponse setObject:@(vertical) forKey:@"isVertical"];
                
                if (![[self.options objectForKey:@"noData"] boolValue]) {
                    NSString *dataString = [imageData base64EncodedStringWithOptions:0];
                    [gifResponse setObject:dataString forKey:@"data"];
                }
                
                NSURL *fileURL = [NSURL fileURLWithPath:path];
                [gifResponse setObject:[fileURL absoluteString] forKey:@"uri"];
                
                NSNumber *fileSizeValue = nil;
                NSError *fileSizeError = nil;
                [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&fileSizeError];
                if (fileSizeValue){
                    [gifResponse setObject:fileSizeValue forKey:@"fileSize"];
                }
                self.callback(@[gifResponse]);
                return;
            }];
            
        }
        // Gif 处理完成，直接返回
        if (isGif) return;
        
        
        image = [self fixOrientation:image];
        
        // If needed, downscale image
        float maxWidth = image.size.width;
        float maxHeight = image.size.height;
        if ([self.options valueForKey:@"maxWidth"]) {
            maxWidth = [[self.options valueForKey:@"maxWidth"] floatValue];
        }
        if ([self.options valueForKey:@"maxHeight"]) {
            maxHeight = [[self.options valueForKey:@"maxHeight"] floatValue];
        }
        image = [self downscaleImageIfNecessary:image maxWidth:maxWidth maxHeight:maxHeight];
        
        NSData *imageData;
        if ([[[self.options objectForKey:@"imageFileType"] stringValue] isEqualToString:@"png"]) {
            imageData = UIImagePNGRepresentation(image);
        }
        else {
            imageData = UIImageJPEGRepresentation(image, [[self.options valueForKey:@"quality"] floatValue]);
        }
        
        if (imageData == nil) {
            self.callback(@[@{@"error": @"未能读取到图片"}]);
            return;
        }
        
        [imageData writeToFile:path atomically:YES];
        
        if (![[self.options objectForKey:@"noData"] boolValue]) {
            NSString *dataString = [imageData base64EncodedStringWithOptions:0]; // base64 encoded image string
            [self.response setObject:dataString forKey:@"data"];
        }
        
        BOOL vertical = (image.size.width < image.size.height) ? YES : NO;
        [self.response setObject:@(vertical) forKey:@"isVertical"];
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        NSString *filePath = [fileURL absoluteString];
        [self.response setObject:filePath forKey:@"uri"];
        
        NSNumber *fileSizeValue = nil;
        NSError *fileSizeError = nil;
        [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&fileSizeError];
        if (fileSizeValue){
            [self.response setObject:fileSizeValue forKey:@"fileSize"];
        }
        
        [self.response setObject:@(image.size.width) forKey:@"width"];
        [self.response setObject:@(image.size.height) forKey:@"height"];
        
        // If storage options are provided, check the skipBackup flag
        if ([self.options objectForKey:@"storageOptions"] && [[self.options objectForKey:@"storageOptions"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *storageOptions = [self.options objectForKey:@"storageOptions"];
            
            if ([[storageOptions objectForKey:@"skipBackup"] boolValue]) {
                [self addSkipBackupAttributeToItemAtPath:path]; // Don't back up the file to iCloud
            }
            
            if ([[storageOptions objectForKey:@"waitUntilSaved"] boolValue] == NO ||
                [[storageOptions objectForKey:@"cameraRoll"] boolValue] == NO ||
                [ImagePickerManager sharedImagePickerController].sourceType != UIImagePickerControllerSourceTypeCamera)
            {
                self.callback(@[self.response]);
            }
        }
        else {
            self.callback(@[self.response]);
        }
    };
    
    // ItemProvider 加载完成的回调
    void (^itemProviderLoadCompletionHandler)(id<NSItemProviderReading> _Nullable object, NSError * _Nullable error) = ^(__kindof id<NSItemProviderReading>  _Nullable object, NSError * _Nullable error) {
        if (error) {
            NSLog(@"error, %@", error.localizedDescription);
        }
        
        if ([object isKindOfClass:UIImage.class]) {
            UIImage *image = (UIImage *)object;
            if (!image) return;
            
            // 由于新的 PhotoKitPickerController 返回的图片是不可编辑的，所以这里就忽略掉 allowsEditing 参数
            PHPickerResult *pickerResult = results.firstObject;
            PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[pickerResult.assetIdentifier] options:nil];
            if (assets.count == 0) {
                if (self.isPhotoLibraryLimitedAccess) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[PHPhotoLibrary sharedPhotoLibrary] presentLimitedLibraryPickerFromViewController:RCTPresentedViewController()];
                    });
                } else {
                    self.callback(@[@{@"error": @"Photo is empty"}]);
                }
                return;
            }
            PHAsset *pickedAsset = assets.lastObject;
            [self getPhotoAssetPHContentEditingInputWithAsset:pickedAsset completionHandler:^(PHContentEditingInput *editingInput) {
                photoAssetImageEditingInputCompletionHandler(editingInput, image, pickedAsset);
            }];
        }
    };
    
    dispatch_block_t dismissCompletionBlock = ^{
        NSItemProvider *itemProvider = results.firstObject.itemProvider;
        if ([itemProvider canLoadObjectOfClass:UIImage.class]) {
            [itemProvider loadObjectOfClass:UIImage.class completionHandler:itemProviderLoadCompletionHandler];
        } else {
            self.callback(@[@{@"didCancel": @YES}]);
        }
    };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:dismissCompletionBlock];
    });
}

/**
 通过 PHAsset 对象获取图片的 PHContentEditingInput 内容
 */
- (void)getPhotoAssetPHContentEditingInputWithAsset:(PHAsset *)asset completionHandler:(void (^)(PHContentEditingInput *))completionHandler API_AVAILABLE(ios(14.0));
{
    PHContentEditingInputRequestOptions *options = [[PHContentEditingInputRequestOptions alloc] init];
    options.networkAccessAllowed = false;
    [asset requestContentEditingInputWithOptions:options completionHandler:^(PHContentEditingInput * _Nullable contentEditingInput, NSDictionary * _Nonnull info) {
        if (contentEditingInput == nil) {
            if (self.isPhotoLibraryLimitedAccess) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[PHPhotoLibrary sharedPhotoLibrary] presentLimitedLibraryPickerFromViewController:RCTPresentedViewController()];
                });
            } else {
                self.callback(@[@{@"error": @"Photo is empty"}]);
            }
        } else {
            completionHandler(contentEditingInput);
        }
    }];
}
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
    self.callback(@[@{@"didCancel": @YES}]);
}
#endif

#pragma mark - iOS 13 及以下
- (void)launchImagePicker:(RNImagePickerTarget)target options:(NSDictionary *)options
{
    self.options = [options mutableCopy];
    [self launchImagePicker:target];
}

- (void)launchImagePicker:(RNImagePickerTarget)target
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startLaunchImagePicker:target];
    });
}

- (void)startLaunchImagePicker: (RNImagePickerTarget)target {
    if (target == RNImagePickerTargetCamera) {
#if TARGET_IPHONE_SIMULATOR
        self.callback(@[@{@"error": @"Camera not available on simulator"}]);
        return;
#else
        [ImagePickerManager sharedImagePickerController].sourceType = UIImagePickerControllerSourceTypeCamera;
        if ([[self.options objectForKey:@"cameraType"] isEqualToString:@"front"]) {
            [ImagePickerManager sharedImagePickerController].cameraDevice = UIImagePickerControllerCameraDeviceFront;
        }
        else { // "back"
            [ImagePickerManager sharedImagePickerController].cameraDevice = UIImagePickerControllerCameraDeviceRear;
        }
#endif
    }
    else { // RNImagePickerTargetLibrarySingleImage
        [ImagePickerManager sharedImagePickerController].sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    
    if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"video"]
        || [[self.options objectForKey:@"mediaType"] isEqualToString:@"mixed"]) {
        
        if ([[self.options objectForKey:@"videoQuality"] isEqualToString:@"high"]) {
            [ImagePickerManager sharedImagePickerController].videoQuality = UIImagePickerControllerQualityTypeHigh;
        }
        else if ([[self.options objectForKey:@"videoQuality"] isEqualToString:@"low"]) {
            [ImagePickerManager sharedImagePickerController].videoQuality = UIImagePickerControllerQualityTypeLow;
        }
        else {
            [ImagePickerManager sharedImagePickerController].videoQuality = UIImagePickerControllerQualityTypeMedium;
        }
        
        id durationLimit = [self.options objectForKey:@"durationLimit"];
        if (durationLimit) {
            [ImagePickerManager sharedImagePickerController].videoMaximumDuration = [durationLimit doubleValue];
            [ImagePickerManager sharedImagePickerController].allowsEditing = NO;
        }
    }
    if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"video"]) {
        [ImagePickerManager sharedImagePickerController].mediaTypes = @[(NSString *)kUTTypeMovie];
    } else if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"mixed"]) {
        [ImagePickerManager sharedImagePickerController].mediaTypes = @[(NSString *)kUTTypeMovie, (NSString *)kUTTypeImage];
    } else {
        [ImagePickerManager sharedImagePickerController].mediaTypes = @[(NSString *)kUTTypeImage];
    }
    
    if ([[self.options objectForKey:@"allowsEditing"] boolValue]) {
        [ImagePickerManager sharedImagePickerController].allowsEditing = true;
    }
    [ImagePickerManager sharedImagePickerController].modalPresentationStyle = UIModalPresentationFullScreen;
    [ImagePickerManager sharedImagePickerController].delegate = self;
    
    // Check permissions
    void (^showPickerViewController)(void) = ^void() {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *root = RCTPresentedViewController();
            [root presentViewController:[ImagePickerManager sharedImagePickerController] animated:YES completion:nil];
        });
    };
    
    if (target == RNImagePickerTargetCamera) {
        [self checkCameraPermissions:^(BOOL granted) {
            if (!granted) {
                self.callback(@[@{@"error": @"Camera permissions not granted"}]);
                return;
            }
            
            showPickerViewController();
        }];
    }
    else { // RNImagePickerTargetLibrarySingleImage
        [self checkPhotosPermissions:^(BOOL granted) {
            if (!granted) {
                self.callback(@[@{@"error": @"Photo library permissions not granted"}]);
                return;
            }
            
            showPickerViewController();
        }];
    }
}

- (NSString * _Nullable)originalFilenameForAsset:(PHAsset * _Nullable)asset assetType:(PHAssetResourceType)type {
    if (!asset) { return nil; }
    
    PHAssetResource *originalResource;
    // Get the underlying resources for the PHAsset (PhotoKit)
    NSArray<PHAssetResource *> *pickedAssetResources = [PHAssetResource assetResourcesForAsset:asset];
    
    // Find the original resource (underlying image) for the asset, which has the desired filename
    for (PHAssetResource *resource in pickedAssetResources) {
        if (resource.type == type) {
            originalResource = resource;
        }
    }
    
    return originalResource.originalFilename;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    dispatch_block_t dismissCompletionBlock = ^{
        
        NSURL *imageURL = info[@"UIImagePickerControllerReferenceURL"];
        NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
        
        NSString *fileName;
        if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
            NSString *tempFileName = [[NSUUID UUID] UUIDString];
            if (imageURL && [[imageURL absoluteString] rangeOfString:@"ext=GIF"].location != NSNotFound) {
                fileName = [tempFileName stringByAppendingString:@".gif"];
            }
            else if ([[[self.options objectForKey:@"imageFileType"] stringValue] isEqualToString:@"png"]) {
                fileName = [tempFileName stringByAppendingString:@".png"];
            }
            else {
                fileName = [tempFileName stringByAppendingString:@".jpg"];
            }
        }
        else {
            NSURL *videoURL = info[UIImagePickerControllerMediaURL];
            fileName = videoURL.lastPathComponent;
        }
        
        // We default to path to the temporary directory
        NSString *path = [[NSTemporaryDirectory()stringByStandardizingPath] stringByAppendingPathComponent:fileName];
        
        // If storage options are provided, we use the documents directory which is persisted
        if ([self.options objectForKey:@"storageOptions"] && [[self.options objectForKey:@"storageOptions"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *storageOptions = [self.options objectForKey:@"storageOptions"];
            
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            path = [documentsDirectory stringByAppendingPathComponent:fileName];
            
            // Creates documents subdirectory, if provided
            if ([storageOptions objectForKey:@"path"]) {
                NSString *newPath = [documentsDirectory stringByAppendingPathComponent:[storageOptions objectForKey:@"path"]];
                NSError *error;
                [[NSFileManager defaultManager] createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:&error];
                if (error) {
                    NSLog(@"Error creating documents subdirectory: %@", error);
                    self.callback(@[@{@"error": error.localizedFailureReason}]);
                    return;
                }
                else {
                    path = [newPath stringByAppendingPathComponent:fileName];
                }
            }
        }
        
        // Create the response object
        self.response = [[NSMutableDictionary alloc] init];
        
        if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) { // PHOTOS
            UIImage *image;
            if ([[self.options objectForKey:@"allowsEditing"] boolValue]) {
                image = [info objectForKey:UIImagePickerControllerEditedImage];
            }
            else {
                image = [info objectForKey:UIImagePickerControllerOriginalImage];
            }
            
            if (imageURL) {
                PHAsset *pickedAsset = [PHAsset fetchAssetsWithALAssetURLs:@[imageURL] options:nil].lastObject;
                NSString *originalFilename = [self originalFilenameForAsset:pickedAsset assetType:PHAssetResourceTypePhoto];
                self.response[@"fileName"] = originalFilename ?: [NSNull null];
                if (pickedAsset.location) {
                    self.response[@"latitude"] = @(pickedAsset.location.coordinate.latitude);
                    self.response[@"longitude"] = @(pickedAsset.location.coordinate.longitude);
                }
                if (pickedAsset.creationDate) {
                    self.response[@"timestamp"] = [[ImagePickerManager ISO8601DateFormatter] stringFromDate:pickedAsset.creationDate];
                }
            }
            
            // GIFs break when resized, so we handle them differently
            if (imageURL && [[imageURL absoluteString] rangeOfString:@"ext=GIF"].location != NSNotFound) {
                ALAssetsLibrary* assetsLibrary = [[ALAssetsLibrary alloc] init];
                [assetsLibrary assetForURL:imageURL resultBlock:^(ALAsset *asset) {
                    ALAssetRepresentation *rep = [asset defaultRepresentation];
                    Byte *buffer = (Byte*)malloc(rep.size);
                    NSUInteger buffered = [rep getBytes:buffer fromOffset:0.0 length:rep.size error:nil];
                    NSData *data = [NSData dataWithBytesNoCopy:buffer length:buffered freeWhenDone:YES];
                    [data writeToFile:path atomically:YES];
                    
                    NSMutableDictionary *gifResponse = [[NSMutableDictionary alloc] init];
                    [gifResponse setObject:@(image.size.width) forKey:@"width"];
                    [gifResponse setObject:@(image.size.height) forKey:@"height"];
                    
                    BOOL vertical = (image.size.width < image.size.height) ? YES : NO;
                    [gifResponse setObject:@(vertical) forKey:@"isVertical"];
                    
                    if (![[self.options objectForKey:@"noData"] boolValue]) {
                        NSString *dataString = [data base64EncodedStringWithOptions:0];
                        [gifResponse setObject:dataString forKey:@"data"];
                    }
                    
                    NSURL *fileURL = [NSURL fileURLWithPath:path];
                    [gifResponse setObject:[fileURL absoluteString] forKey:@"uri"];
                    
                    NSNumber *fileSizeValue = nil;
                    NSError *fileSizeError = nil;
                    [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&fileSizeError];
                    if (fileSizeValue){
                        [gifResponse setObject:fileSizeValue forKey:@"fileSize"];
                    }
                    
                    self.callback(@[gifResponse]);
                } failureBlock:^(NSError *error) {
                    self.callback(@[@{@"error": error.localizedFailureReason}]);
                }];
                return;
            }
            
            image = [self fixOrientation:image];  // Rotate the image for upload to web
            
            // If needed, downscale image
            float maxWidth = image.size.width;
            float maxHeight = image.size.height;
            if ([self.options valueForKey:@"maxWidth"]) {
                maxWidth = [[self.options valueForKey:@"maxWidth"] floatValue];
            }
            if ([self.options valueForKey:@"maxHeight"]) {
                maxHeight = [[self.options valueForKey:@"maxHeight"] floatValue];
            }
            image = [self downscaleImageIfNecessary:image maxWidth:maxWidth maxHeight:maxHeight];
            
            NSData *data;
            if ([[[self.options objectForKey:@"imageFileType"] stringValue] isEqualToString:@"png"]) {
                data = UIImagePNGRepresentation(image);
            }
            else {
                data = UIImageJPEGRepresentation(image, [[self.options valueForKey:@"quality"] floatValue]);
            }
            
            if (data == nil) {
                self.callback(@[@{@"error": @"未能读取到图片"}]);
                return;
            }
            
            [data writeToFile:path atomically:YES];
            
            if (![[self.options objectForKey:@"noData"] boolValue]) {
                NSString *dataString = [data base64EncodedStringWithOptions:0]; // base64 encoded image string
                [self.response setObject:dataString forKey:@"data"];
            }
            
            BOOL vertical = (image.size.width < image.size.height) ? YES : NO;
            [self.response setObject:@(vertical) forKey:@"isVertical"];
            NSURL *fileURL = [NSURL fileURLWithPath:path];
            NSString *filePath = [fileURL absoluteString];
            [self.response setObject:filePath forKey:@"uri"];
            
            // add ref to the original image
            NSString *origURL = [imageURL absoluteString];
            if (origURL) {
                [self.response setObject:origURL forKey:@"origURL"];
            }
            
            NSNumber *fileSizeValue = nil;
            NSError *fileSizeError = nil;
            [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&fileSizeError];
            if (fileSizeValue){
                [self.response setObject:fileSizeValue forKey:@"fileSize"];
            }
            
            [self.response setObject:@(image.size.width) forKey:@"width"];
            [self.response setObject:@(image.size.height) forKey:@"height"];
            
            NSDictionary *storageOptions = [self.options objectForKey:@"storageOptions"];
            if (storageOptions && [[storageOptions objectForKey:@"cameraRoll"] boolValue] == YES && [ImagePickerManager sharedImagePickerController].sourceType == UIImagePickerControllerSourceTypeCamera) {
                ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                if ([[storageOptions objectForKey:@"waitUntilSaved"] boolValue]) {
                    [library writeImageToSavedPhotosAlbum:image.CGImage metadata:[info valueForKey:UIImagePickerControllerMediaMetadata] completionBlock:^(NSURL *assetURL, NSError *error) {
                        if (error) {
                            NSLog(@"Error while saving picture into photo album");
                        } else {
                            // when the image has been saved in the photo album
                            if (assetURL) {
                                PHAsset *capturedAsset = [PHAsset fetchAssetsWithALAssetURLs:@[assetURL] options:nil].lastObject;
                                NSString *originalFilename = [self originalFilenameForAsset:capturedAsset assetType:PHAssetResourceTypePhoto];
                                self.response[@"fileName"] = originalFilename ?: [NSNull null];
                                // This implementation will never have a location for the captured image, it needs to be added manually with CoreLocation code here.
                                if (capturedAsset.creationDate) {
                                    self.response[@"timestamp"] = [[ImagePickerManager ISO8601DateFormatter] stringFromDate:capturedAsset.creationDate];
                                }
                            }
                            self.callback(@[self.response]);
                        }
                    }];
                } else {
                    [library writeImageToSavedPhotosAlbum:image.CGImage metadata:[info valueForKey:UIImagePickerControllerMediaMetadata] completionBlock:nil];
                }
            }
        }
        else { // VIDEO
            NSURL *videoRefURL = info[UIImagePickerControllerReferenceURL];
            NSURL *videoURL = info[UIImagePickerControllerMediaURL];
            NSURL *videoDestinationURL = [NSURL fileURLWithPath:path];
            
            if (videoRefURL) {
                PHAsset *pickedAsset = [PHAsset fetchAssetsWithALAssetURLs:@[videoRefURL] options:nil].lastObject;
                NSString *originalFilename = [self originalFilenameForAsset:pickedAsset assetType:PHAssetResourceTypeVideo];
                self.response[@"fileName"] = originalFilename ?: [NSNull null];
                if (pickedAsset.location) {
                    self.response[@"latitude"] = @(pickedAsset.location.coordinate.latitude);
                    self.response[@"longitude"] = @(pickedAsset.location.coordinate.longitude);
                }
                if (pickedAsset.creationDate) {
                    self.response[@"timestamp"] = [[ImagePickerManager ISO8601DateFormatter] stringFromDate:pickedAsset.creationDate];
                }
            }
            
            if ([videoURL.URLByResolvingSymlinksInPath.path isEqualToString:videoDestinationURL.URLByResolvingSymlinksInPath.path] == NO) {
                NSFileManager *fileManager = [NSFileManager defaultManager];
                
                // Delete file if it already exists
                if ([fileManager fileExistsAtPath:videoDestinationURL.path]) {
                    [fileManager removeItemAtURL:videoDestinationURL error:nil];
                }
                
                if (videoURL) { // Protect against reported crash
                    NSError *error = nil;
                    [fileManager moveItemAtURL:videoURL toURL:videoDestinationURL error:&error];
                    if (error) {
                        self.callback(@[@{@"error": error.localizedFailureReason}]);
                        return;
                    }
                }
            }
            
            [self.response setObject:videoDestinationURL.absoluteString forKey:@"uri"];
            if (videoRefURL.absoluteString) {
                [self.response setObject:videoRefURL.absoluteString forKey:@"origURL"];
            }
            
            NSDictionary *storageOptions = [self.options objectForKey:@"storageOptions"];
            if (storageOptions && [[storageOptions objectForKey:@"cameraRoll"] boolValue] == YES && [ImagePickerManager sharedImagePickerController].sourceType == UIImagePickerControllerSourceTypeCamera) {
                ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                [library writeVideoAtPathToSavedPhotosAlbum:videoDestinationURL completionBlock:^(NSURL *assetURL, NSError *error) {
                    if (error) {
                        self.callback(@[@{@"error": error.localizedFailureReason}]);
                        return;
                    } else {
                        NSLog(@"Save video succeed.");
                        if ([[storageOptions objectForKey:@"waitUntilSaved"] boolValue]) {
                            if (assetURL) {
                                PHAsset *capturedAsset = [PHAsset fetchAssetsWithALAssetURLs:@[assetURL] options:nil].lastObject;
                                NSString *originalFilename = [self originalFilenameForAsset:capturedAsset assetType:PHAssetResourceTypeVideo];
                                self.response[@"fileName"] = originalFilename ?: [NSNull null];
                                // This implementation will never have a location for the captured image, it needs to be added manually with CoreLocation code here.
                                if (capturedAsset.creationDate) {
                                    self.response[@"timestamp"] = [[ImagePickerManager ISO8601DateFormatter] stringFromDate:capturedAsset.creationDate];
                                }
                            }
                            
                            self.callback(@[self.response]);
                        }
                    }
                }];
            }
        }
        
        // If storage options are provided, check the skipBackup flag
        if ([self.options objectForKey:@"storageOptions"] && [[self.options objectForKey:@"storageOptions"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *storageOptions = [self.options objectForKey:@"storageOptions"];
            
            if ([[storageOptions objectForKey:@"skipBackup"] boolValue]) {
                [self addSkipBackupAttributeToItemAtPath:path]; // Don't back up the file to iCloud
            }
            
            if ([[storageOptions objectForKey:@"waitUntilSaved"] boolValue] == NO ||
                [[storageOptions objectForKey:@"cameraRoll"] boolValue] == NO ||
                [ImagePickerManager sharedImagePickerController].sourceType != UIImagePickerControllerSourceTypeCamera)
            {
                self.callback(@[self.response]);
            }
        }
        else {
            self.callback(@[self.response]);
        }
        picker.delegate = nil;
    };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:dismissCompletionBlock];
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:^{
            self.callback(@[@{@"didCancel": @YES}]);
            picker.delegate = nil;
        }];
    });
}

#pragma mark - UIPopoverPresentationControllerDelegate

- (void)popoverPresentationController:(UIPopoverPresentationController *)popoverPresentationController
          willRepositionPopoverToRect:(inout CGRect *)rect inView:(inout UIView  * __nonnull * __nonnull)view {
    CGRect bounds = (*view).bounds;
    *rect = CGRectMake(bounds.size.width / 2.0, bounds.size.height, 1.0, 1.0);
}

#pragma mark - Helpers

/**
 检查相机权限
 */
- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    } else {
        callback(NO);
    }
}

/**
 检查相册权限
 */
- (void)checkPhotosPermissions:(void(^)(BOOL granted))callback
{
    if (@available(iOS 14, *)) {
        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (status == PHAuthorizationStatusAuthorized) {
            callback(YES);
            return;
        } else if (status == PHAuthorizationStatusLimited) {
            self.isPhotoLibraryLimitedAccess = YES;
            callback(YES);
            return;
        } else if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) {
                    callback(YES);
                    return;
                }
                else {
                    if (status == PHAuthorizationStatusLimited) {
                        self.isPhotoLibraryLimitedAccess = YES;
                        callback(YES);
                        return;
                    } else {
                        callback(NO);
                        return;
                    }
                }
            }];
        }
        else {
            callback(NO);
        }
        #endif
    } else {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusAuthorized) {
            callback(YES);
            return;
        } else if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) {
                    callback(YES);
                    return;
                }
                else {
                    callback(NO);
                    return;
                }
            }];
        }
        else {
            callback(NO);
        }
    }
}

/**
 根据传入的最大宽度与最大高度判断是否有必要进行裁剪
 */
- (UIImage*)downscaleImageIfNecessary:(UIImage*)image maxWidth:(float)maxWidth maxHeight:(float)maxHeight
{
    UIImage* newImage = image;
    
    // Nothing to do here
    if (image.size.width <= maxWidth && image.size.height <= maxHeight) {
        return newImage;
    }
    
    CGSize scaledSize = CGSizeMake(image.size.width, image.size.height);
    if (maxWidth < scaledSize.width) {
        scaledSize = CGSizeMake(maxWidth, (maxWidth / scaledSize.width) * scaledSize.height);
    }
    if (maxHeight < scaledSize.height) {
        scaledSize = CGSizeMake((maxHeight / scaledSize.height) * scaledSize.width, maxHeight);
    }
    
    // If the pixels are floats, it causes a white line in iOS8 and probably other versions too
    scaledSize.width = (int)scaledSize.width;
    scaledSize.height = (int)scaledSize.height;
    
    UIGraphicsBeginImageContext(scaledSize); // this will resize
    [image drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];
    newImage = UIGraphicsGetImageFromCurrentImageContext();
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }
    UIGraphicsEndImageContext();
    
    return newImage;
}

/**
 修正屏幕方向
 */
- (UIImage *)fixOrientation:(UIImage *)srcImg {
    if (srcImg.imageOrientation == UIImageOrientationUp) {
        return srcImg;
    }
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    switch (srcImg.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, srcImg.size.width, srcImg.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, srcImg.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, srcImg.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (srcImg.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, srcImg.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, srcImg.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    CGContextRef ctx = CGBitmapContextCreate(NULL, srcImg.size.width, srcImg.size.height, CGImageGetBitsPerComponent(srcImg.CGImage), 0, CGImageGetColorSpace(srcImg.CGImage), CGImageGetBitmapInfo(srcImg.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (srcImg.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            CGContextDrawImage(ctx, CGRectMake(0,0,srcImg.size.height,srcImg.size.width), srcImg.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,srcImg.size.width,srcImg.size.height), srcImg.CGImage);
            break;
    }
    
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

- (BOOL)addSkipBackupAttributeToItemAtPath:(NSString *) filePathString
{
    NSURL* URL= [NSURL fileURLWithPath: filePathString];
    if ([[NSFileManager defaultManager] fileExistsAtPath: [URL path]]) {
        NSError *error = nil;
        BOOL success = [URL setResourceValue: [NSNumber numberWithBool: YES]
                                      forKey: NSURLIsExcludedFromBackupKey error: &error];
        
        if(!success){
            NSLog(@"Error excluding %@ from backup %@", [URL lastPathComponent], error);
        }
        return success;
    }
    else {
        NSLog(@"Error setting skip backup attribute: file not found");
        return NO;
    }
}

#pragma mark - Class Methods
+ (NSDateFormatter * _Nonnull)ISO8601DateFormatter {
    static NSDateFormatter *ISO8601DateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ISO8601DateFormatter = [[NSDateFormatter alloc] init];
        NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        ISO8601DateFormatter.locale = enUSPOSIXLocale;
        ISO8601DateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        ISO8601DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });
    return ISO8601DateFormatter;
}



@end
