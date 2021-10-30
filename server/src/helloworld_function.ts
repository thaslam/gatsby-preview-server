export const handler = async (event: any = {}, context: any = {}): Promise<any> => {
    console.log('Event: ', event);
    const responseMessage = 'Hello, World!';

    return {
        statusCode: 200,
        headers: {
        'Content-Type': 'application/json',
        },
        body: JSON.stringify({
        message: responseMessage,
        }),
    }
};