# react-native-livephoto example

Demo app for the library: generates a Live Photo from `src/assets/sample.mov`, displays it with `<LivePhotoView>` and saves it to Photos.

Run from the repository root:

```sh
npm install
npm run example start   # Metro
npm run example ios     # build and run (CocoaPods are installed automatically)
```

The app resolves `react-native-livephoto` to the local `src/`, so JS changes apply immediately; native changes need a rebuild.
