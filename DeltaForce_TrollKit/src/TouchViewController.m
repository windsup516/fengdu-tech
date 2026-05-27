// TouchViewController - 触摸事件视图控制器
// 配合 TouchMainWindow 捕获和处理触摸事件

#import "TouchViewController.h"

@implementation TouchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = NO;
    
    // 透明背景视图
    self.backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundView.backgroundColor = [UIColor clearColor];
    self.backgroundView.userInteractionEnabled = NO;
    [self.view addSubview:self.backgroundView];
}

@end
