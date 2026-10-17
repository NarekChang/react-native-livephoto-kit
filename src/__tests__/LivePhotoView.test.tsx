import { describe, expect, it, jest } from '@jest/globals';
import { fireEvent, render, screen } from '@testing-library/react-native';
import { StyleSheet } from 'react-native';
import { LivePhotoView } from '../LivePhotoView.ios';

const files = { photoUri: 'file:///p.jpg', videoUri: 'file:///v.mov' };

describe('LivePhotoView', () => {
  it('clips to its border radius by default, like Image', async () => {
    await render(
      <LivePhotoView
        testID="view"
        source={files}
        style={{ borderRadius: 12 }}
      />
    );
    expect(StyleSheet.flatten(screen.getByTestId('view').props.style)).toEqual({
      overflow: 'hidden',
      borderRadius: 12,
    });
  });

  it('lets the style override the clipping', async () => {
    await render(
      <LivePhotoView
        testID="view"
        source={files}
        style={{ overflow: 'visible' }}
      />
    );
    expect(
      StyleSheet.flatten(screen.getByTestId('view').props.style).overflow
    ).toBe('visible');
  });

  it('maps autoplay and passes event payloads without nativeEvent', async () => {
    const onLoad = jest.fn();
    const onError = jest.fn();
    await render(
      <LivePhotoView
        testID="view"
        source={files}
        autoplay
        onLoad={onLoad}
        onError={onError}
      />
    );
    const view = screen.getByTestId('view');
    expect(view.props.autoplay).toBe('hint');

    await fireEvent(view, 'load', { nativeEvent: { width: 3, height: 4 } });
    expect(onLoad).toHaveBeenCalledWith({ width: 3, height: 4 });

    await fireEvent(view, 'error', {
      nativeEvent: { code: 'E_LOAD', message: 'bad pair' },
    });
    expect(onError.mock.calls[0]![0]).toMatchObject({
      name: 'LivePhotoError',
      code: 'E_LOAD',
      message: 'bad pair',
    });
  });
});
